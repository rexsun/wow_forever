--[[
	Korean Localization
--]]

local ADDON = ...
local L = LibStub('AceLocale-3.0'):NewLocale(ADDON, 'koKR')
if not L then return end

--keybindings
L.OpenBags = '소지품 온/오프'
L.OpenBank = '은행 온/오프'
L.OpenGuild = '길드 금고 온/오프'
L.OpenVault = '공허 보관 온/오프'

--terminal
L.Commands = '명령어:'
L.CmdShowInventory = '소지품 온/오프'
L.CmdShowBank = '은행 온/오프'
L.CmdShowGuild = '길드 금고 온/오프'
L.CmdShowVault = '공허 보관 온/오프'
L.CmdShowVersion = '현재 버전 정보 출력'
L.CmdShowOptions = '설정메뉴 열기'
L.CmdReset = '설정 및 캐시 데이터 삭제'
L.ResetConfirm = '정말 %s을(를) 초기화하시겠습니까?|n모든 설정과 캐시 데이터가 손실됩니다.'
L.SkinError = '스킨 적용 오류.'
L.UpgradeError = '설정을 업그레이드하는 중 문제가 발생했습니다. 문제가 계속되면 설정을 초기화해 보세요.'

--titles
L.TitleBags = '%s의 소지품'
L.TitleBank = '%s의 은행'
L.TitleVault = '%s의 공허'
L.NormalBags = '일반 가방'
L.TradeBags = '직업 가방'
L.AmmoBags = '탄약 가방'

--tooltips
L.Bags = '가방'
L.Drag = '<드래그>'
L.BrowseItems = '아이템 찾아보기'
L.HideBag = '이 가방을 숨기려면 클릭하세요.'
L.ShowBag = '이 가방을 보려면 클릭하세요.'
L.GuildFunds = '길드 금고'
L.NumAllowed = '%s 허용'
L.NumWithdraw = '%d 출금'
L.NumDeposit = '%d 입금'
L.NumRemaining = '%s 남음'
L.WarbandMoney = '전투부대 은행 자금'
L.OfflineViewing = '오프라인 보기'
L.Others = '기타'

--menus
L.Characters = '캐릭터'
L.Guilds = '길드'
L.Locations = '위치'
L.EnterDescription = '설명 입력:'
L.ServerSorting = '서버 측 정렬'
L.ReverseSorting = '역순 정렬'
L.PartialFirst = '부분 묶음 우선'
L.CleanupOptions = '정리 옵션'
L.IncludeReagents = '재료 포함'
L.LockItems = '아이템 슬롯 잠금'

--dialogs
L.AskMafia = '마피아에 문의'
L.ConfirmDelete = '%s의 캐시된 데이터를 삭제하시겠습니까?'
L.ConfirmTransfer = '어떤 아이템든 보관하면 모든 수정 사항이 제거되고 거래 및 환불이 불가능합니다.|n|n계속 하시겠습니까?'
L.CannotPurchaseVault = '공허 보관 서비스를 해제할 충분한 금액이 없습니다.|n|n|cffff2020금액: %s|r'
L.PurchaseVault = '공허 보관 서비스를 해제할까요?|n|n|cffffd200금액:|r %s'
L.ConfigurationMode = '현재 클라이언트 측 정렬 구성 모드입니다.|n|n정렬할 때 슬롯을 잠글지 여부를 전환하려면 아이템 슬롯을 클릭하세요.'
L.OutOfDate = '|cffffd200%s|r 버전이 만료되었을 수 있습니다!|n%s에서 |cff82c5ff%s|r 버전을 사용 중이라고 보고했습니다. 사실이라면 업데이트해 주세요.'
L.InvalidVersion = '사용 중인 |cffffd200%s|r 파일이 손상되었거나 불법 복제본입니다.|n공식 빌드를 무료로 다운로드하세요.'
