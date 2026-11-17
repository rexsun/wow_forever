"""Capture one process tree's audio with WASAPI process loopback (Windows 10 build 20348+ / Windows 11)."""

from __future__ import annotations

import ctypes
import threading
import time
from ctypes import POINTER, Structure, byref, c_int, c_longlong, c_ubyte, c_uint32, c_uint64, c_ulong, c_ushort, c_void_p, c_wchar_p, wintypes
from typing import Callable

import comtypes
import numpy as np
from comtypes import COMMETHOD, COMObject, GUID, HRESULT, IUnknown

from detector import SAMPLE_RATE

CHANNELS = 2
BITS = 16
VT_BLOB = 65
ACTIVATION_TYPE_PROCESS_LOOPBACK = 1
LOOPBACK_INCLUDE_TARGET_PROCESS_TREE = 0
SHAREMODE_SHARED = 0
STREAMFLAGS_LOOPBACK = 0x00020000
STREAMFLAGS_EVENTCALLBACK = 0x00040000
BUFFERFLAGS_SILENT = 0x2
BUFFER_DURATION_100NS = 1_000_000
ACTIVATE_TIMEOUT_S = 5.0
WAIT_MS = 200
WAIT_FAILED = 0xFFFFFFFF
PROCESS_LOOPBACK_DEVICE = "VAD\\Process_Loopback"


class CaptureError(RuntimeError):
    pass


class WAVEFORMATEX(Structure):
    _pack_ = 1
    _fields_ = [
        ("wFormatTag", c_ushort), ("nChannels", c_ushort), ("nSamplesPerSec", c_ulong),
        ("nAvgBytesPerSec", c_ulong), ("nBlockAlign", c_ushort), ("wBitsPerSample", c_ushort),
        ("cbSize", c_ushort),
    ]


class PROCESS_LOOPBACK_PARAMS(Structure):
    _fields_ = [("TargetProcessId", wintypes.DWORD), ("ProcessLoopbackMode", c_int)]


class ACTIVATION_PARAMS(Structure):
    _fields_ = [("ActivationType", c_int), ("ProcessLoopbackParams", PROCESS_LOOPBACK_PARAMS)]


class BLOB(Structure):
    _fields_ = [("cbSize", c_ulong), ("pBlobData", c_void_p)]


class PROPVARIANT(Structure):
    _fields_ = [("vt", c_ushort), ("r1", c_ushort), ("r2", c_ushort), ("r3", c_ushort), ("blob", BLOB)]


class IAgileObject(IUnknown):
    _iid_ = GUID("{94EA2B94-E9CC-49E0-C0FF-EE64CA8F5B90}")
    _methods_ = []


class IActivateAudioInterfaceAsyncOperation(IUnknown):
    _iid_ = GUID("{72A22D78-CDE4-431D-B8CC-843A71199B6D}")
    _methods_ = [
        COMMETHOD([], HRESULT, "GetActivateResult",
                  (["out"], POINTER(ctypes.c_long), "activateResult"),
                  (["out"], POINTER(POINTER(IUnknown)), "activatedInterface")),
    ]


class IActivateAudioInterfaceCompletionHandler(IUnknown):
    _iid_ = GUID("{41D949AB-9862-444A-80F6-C261334DA5EB}")
    _methods_ = [
        COMMETHOD([], HRESULT, "ActivateCompleted",
                  (["in"], POINTER(IActivateAudioInterfaceAsyncOperation), "activateOperation")),
    ]


class IAudioCaptureClient(IUnknown):
    _iid_ = GUID("{C8ADBD64-E71E-48A0-A4DE-185C395CD317}")
    _methods_ = [
        COMMETHOD([], HRESULT, "GetBuffer",
                  (["out"], POINTER(POINTER(c_ubyte)), "ppData"),
                  (["out"], POINTER(c_uint32), "pNumFramesToRead"),
                  (["out"], POINTER(wintypes.DWORD), "pdwFlags"),
                  (["out"], POINTER(c_uint64), "pu64DevicePosition"),
                  (["out"], POINTER(c_uint64), "pu64QPCPosition")),
        COMMETHOD([], HRESULT, "ReleaseBuffer", (["in"], c_uint32, "NumFramesRead")),
        COMMETHOD([], HRESULT, "GetNextPacketSize", (["out"], POINTER(c_uint32), "pNumFramesInNextPacket")),
    ]


class IAudioClient(IUnknown):
    _iid_ = GUID("{1CB9AD4C-DBFA-4C32-B178-C2F568A703B2}")
    _methods_ = [
        COMMETHOD([], HRESULT, "Initialize",
                  (["in"], c_int, "ShareMode"), (["in"], wintypes.DWORD, "StreamFlags"),
                  (["in"], c_longlong, "hnsBufferDuration"), (["in"], c_longlong, "hnsPeriodicity"),
                  (["in"], POINTER(WAVEFORMATEX), "pFormat"), (["in"], POINTER(GUID), "AudioSessionGuid")),
        COMMETHOD([], HRESULT, "GetBufferSize", (["out"], POINTER(c_uint32), "pNumBufferFrames")),
        COMMETHOD([], HRESULT, "GetStreamLatency", (["out"], POINTER(c_longlong), "phnsLatency")),
        COMMETHOD([], HRESULT, "GetCurrentPadding", (["out"], POINTER(c_uint32), "pNumPaddingFrames")),
        COMMETHOD([], HRESULT, "IsFormatSupported",
                  (["in"], c_int, "ShareMode"), (["in"], POINTER(WAVEFORMATEX), "pFormat"),
                  (["out"], POINTER(POINTER(WAVEFORMATEX)), "ppClosestMatch")),
        COMMETHOD([], HRESULT, "GetMixFormat", (["out"], POINTER(POINTER(WAVEFORMATEX)), "ppDeviceFormat")),
        COMMETHOD([], HRESULT, "GetDevicePeriod",
                  (["out"], POINTER(c_longlong), "phnsDefaultDevicePeriod"),
                  (["out"], POINTER(c_longlong), "phnsMinimumDevicePeriod")),
        COMMETHOD([], HRESULT, "Start"),
        COMMETHOD([], HRESULT, "Stop"),
        COMMETHOD([], HRESULT, "Reset"),
        COMMETHOD([], HRESULT, "SetEventHandle", (["in"], c_void_p, "eventHandle")),
        COMMETHOD([], HRESULT, "GetService",
                  (["in"], POINTER(GUID), "riid"), (["out"], POINTER(POINTER(IUnknown)), "ppv")),
    ]


class _CompletionHandler(COMObject):
    # Must be agile: ActivateAudioInterfaceAsync calls back on a worker thread.
    _com_interfaces_ = [IActivateAudioInterfaceCompletionHandler, IAgileObject]

    def __init__(self) -> None:
        super().__init__()
        self.completed = threading.Event()

    def ActivateCompleted(self, this, operation) -> int:
        self.completed.set()
        return 0


_kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
_kernel32.CreateEventW.restype = wintypes.HANDLE
_kernel32.CreateEventW.argtypes = [c_void_p, wintypes.BOOL, wintypes.BOOL, c_wchar_p]
_kernel32.WaitForSingleObject.restype = wintypes.DWORD
_kernel32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
_kernel32.CloseHandle.argtypes = [wintypes.HANDLE]


def _activate_audio_interface_async():
    try:
        fn = ctypes.WinDLL("Mmdevapi").ActivateAudioInterfaceAsync
    except (OSError, AttributeError) as exc:
        raise CaptureError("this Windows version cannot capture a single app's audio") from exc
    fn.restype = HRESULT
    fn.argtypes = [c_wchar_p, POINTER(GUID), POINTER(PROPVARIANT),
                   POINTER(IActivateAudioInterfaceCompletionHandler),
                   POINTER(POINTER(IActivateAudioInterfaceAsyncOperation))]
    return fn


def _capture_format() -> WAVEFORMATEX:
    block = CHANNELS * BITS // 8
    return WAVEFORMATEX(1, CHANNELS, SAMPLE_RATE, SAMPLE_RATE * block, block, BITS, 0)


def _open_client(pid: int) -> IAudioClient:
    params = ACTIVATION_PARAMS(ACTIVATION_TYPE_PROCESS_LOOPBACK,
                               PROCESS_LOOPBACK_PARAMS(pid, LOOPBACK_INCLUDE_TARGET_PROCESS_TREE))
    variant = PROPVARIANT(vt=VT_BLOB, blob=BLOB(ctypes.sizeof(params), ctypes.cast(byref(params), c_void_p)))
    handler = _CompletionHandler()
    operation = POINTER(IActivateAudioInterfaceAsyncOperation)()
    try:
        _activate_audio_interface_async()(
            PROCESS_LOOPBACK_DEVICE, byref(IAudioClient._iid_), byref(variant),
            handler.QueryInterface(IActivateAudioInterfaceCompletionHandler), byref(operation))
    except OSError as exc:
        raise CaptureError(f"could not request the game's audio: {exc}") from exc
    if not handler.completed.wait(ACTIVATE_TIMEOUT_S):
        raise CaptureError("Windows did not answer the request for the game's audio")
    result, unknown = operation.GetActivateResult()
    if result < 0 or not unknown:
        raise CaptureError(f"Windows refused to capture the game's audio (HRESULT 0x{result & 0xFFFFFFFF:08X})")
    return unknown.QueryInterface(IAudioClient)


def capture_process(pid: int, on_chunk: Callable[[float, np.ndarray], None], stop: threading.Event) -> None:
    """Blocks until stop is set, calling on_chunk(perf_counter time of first sample, mono float32 samples)."""
    comtypes.CoInitializeEx(comtypes.COINIT_MULTITHREADED)
    event = None
    client = capture = None
    try:
        client = _open_client(pid)
        fmt = _capture_format()
        client.Initialize(SHAREMODE_SHARED, STREAMFLAGS_LOOPBACK | STREAMFLAGS_EVENTCALLBACK,
                          BUFFER_DURATION_100NS, 0, byref(fmt), None)
        event = _kernel32.CreateEventW(None, False, False, None)
        if not event:
            raise CaptureError(f"CreateEvent failed ({ctypes.get_last_error()})")
        client.SetEventHandle(event)
        capture = client.GetService(byref(IAudioCaptureClient._iid_)).QueryInterface(IAudioCaptureClient)
        client.Start()
        try:
            while not stop.is_set():
                if _kernel32.WaitForSingleObject(event, WAIT_MS) == WAIT_FAILED:
                    raise CaptureError(f"waiting for audio failed ({ctypes.get_last_error()})")
                _drain(capture, fmt.nBlockAlign, on_chunk)
        finally:
            client.Stop()
    except comtypes.COMError as exc:
        raise CaptureError(f"audio capture failed: {exc}") from exc
    finally:
        if event:
            _kernel32.CloseHandle(event)
        # COM pointers must be released before the apartment is torn down.
        client = capture = None
        comtypes.CoUninitialize()


def _drain(capture: IAudioCaptureClient, block_align: int, on_chunk: Callable[[float, np.ndarray], None]) -> None:
    while capture.GetNextPacketSize():
        data, frames, flags, _, qpc = capture.GetBuffer()
        try:
            if flags & BUFFERFLAGS_SILENT or not data:
                stereo = np.zeros((frames, CHANNELS), dtype=np.float32)
            else:
                raw = np.frombuffer(ctypes.string_at(data, frames * block_align), dtype=np.int16)
                stereo = raw.reshape(-1, CHANNELS).astype(np.float32) / 32768.0
        finally:
            capture.ReleaseBuffer(frames)
        # The QPC position is in 100 ns units, the same clock as time.perf_counter().
        when = qpc * 1e-7 if qpc else time.perf_counter() - frames / SAMPLE_RATE
        on_chunk(when, stereo.mean(axis=1))
