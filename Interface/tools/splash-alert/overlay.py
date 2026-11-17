"""Full-screen, click-through alert shown on every monitor without taking focus."""

from __future__ import annotations

import logging
from dataclasses import dataclass

from PySide6.QtCore import QObject, QRect, Qt, QTimer, Signal
from PySide6.QtGui import QColor, QFont, QFontDatabase, QGuiApplication, QPainter
from PySide6.QtWidgets import QWidget

log = logging.getLogger("splash-alert")


@dataclass(frozen=True)
class OverlayStyle:
    text: str = "🎣 Bite!"
    font_family: str = "Maple Mono NF CN"
    font_points: int = 64
    text_color: str = "#ADD8E6"
    background: str = "#000000"
    opacity: float = 0.2
    duration_s: float = 3.0


class _ScreenOverlay(QWidget):
    def __init__(self, style: OverlayStyle, geometry: QRect, text: str) -> None:
        super().__init__(None, Qt.WindowType.FramelessWindowHint | Qt.WindowType.WindowStaysOnTopHint
                         | Qt.WindowType.Tool | Qt.WindowType.WindowTransparentForInput
                         | Qt.WindowType.WindowDoesNotAcceptFocus)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)
        self.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents)
        self.setGeometry(geometry)
        self._background = QColor(style.background)
        self._background.setAlphaF(style.opacity)
        self._text_color = QColor(style.text_color)
        self._text = text
        # Points scale with each monitor's DPI, so the text keeps its size at 1080p, 1440p and 4K.
        self._font = QFont(style.font_family)
        self._font.setPointSize(style.font_points)

    def paintEvent(self, _event) -> None:
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.TextAntialiasing)
        painter.fillRect(self.rect(), self._background)
        painter.setFont(self._font)
        painter.setPen(self._text_color)
        painter.drawText(self.rect(), Qt.AlignmentFlag.AlignCenter, self._text)


class Overlay(QObject):
    """show_bite, show_message and dismiss may be emitted from any thread; the windows live on the GUI thread."""

    show_bite = Signal()
    show_message = Signal(str)
    dismiss = Signal()

    def __init__(self, style: OverlayStyle) -> None:
        super().__init__()
        self._style = style
        self._windows: list[_ScreenOverlay] = []
        self._timer = QTimer(self)
        self._timer.setSingleShot(True)
        self._timer.timeout.connect(self._hide)
        self.show_bite.connect(lambda: self._show(style.text))
        self.show_message.connect(self._show)
        self.dismiss.connect(self._hide)
        if style.font_family not in QFontDatabase.families():
            log.warning("Font %r is not installed; using the system font.", style.font_family)

    def _show(self, text: str) -> None:
        self._hide()
        self._windows = [_ScreenOverlay(self._style, screen.geometry(), text) for screen in QGuiApplication.screens()]
        for window in self._windows:
            window.show()
            window.raise_()
        self._timer.start(int(self._style.duration_s * 1000))

    def _hide(self) -> None:
        self._timer.stop()
        for window in self._windows:
            window.close()
            window.deleteLater()
        self._windows = []
