-- 11-22 用户「增加一下M语的真实感，可以适当加一些可以理解的错别字」：要 BUFF / 要吃喝的那句话，大约每 3 句有 1 句带一个手滑错字（同音 / 多敲一下）
--   放在按需加载的 _GroupMage（组队信标登录内存没余量）：信标 DC.AskPhrase 里只留一行「有 DC.Typo 就过一遍」；
--   不是法师默认登录就加载（法师吃喝的野外弹框 / 交易道谢默认开），没加载 = 不带错字，照常发
--   只改称呼 / 请求 / 结尾片段，在填要的东西之前换：⛔ 不碰 BUFF 名 / 水 / 面包（法师端靠它认）、句尾等级、称呼词（义父 → ns.ApplyCall 换）
--   ⛔ 错字别凑出「不用 / 不要 / 有了…」；固定说法（rec.askFixed）不带；rec.askTypo = false 关
--   预览 = 实发：错字定在这一组（c[4]），发出去换下一组时才重新抽
-- 11-22 用户「语句变体多一些，让人看不出来」：每段再加 6 种（6 → 12，对一个人 12×12×12 = 1728 种）；
--   句式也变（c[5]，和错字一起开关）：约 1/6 不带称呼、约 1/6 不带结尾，其余照常
local _, ns = ...; ns = _G.GearInsightForever or ns
local DC = ns.DungeonChat
if not DC then return end
local CL = function(cn, en) return ns.ChatL(cn, en) end
DC.TYPO_P = 3
local baseParts = DC.AskParts
DC.ASK_N = 12
function DC.AskParts()
    local P = baseParts()
    local more = {
        call1 = { CL("义父在吗，", "Hey there friend, "), CL("嘿 义父，", "Yo friend, "), CL("那个 义父，", "Um friend, "),
            CL("义父义父，", "Hey hey friend, "), CL("义父哈喽，", "Hiya friend, "), CL("路过的义父，", "Hey passing friend, ") },
        callN = { CL("哈喽各位义父，", "Yo all, "), CL("在座的义父们，", "Hiya folks, "), CL("那个 各位义父，", "Um guys, "),
            CL("嘿 义父们，", "Hey hey all, "), CL("队里的义父们，", "Hi team, "), CL("各位路过的义父，", "Hey there all, ") },
        reqBuff = { CL("%s来一个呗，", "%s pls? "), CL("能不能给个%s，", "can I get %s? "), CL("顺手给个%s呗，", "could you toss %s on me? "),
            CL("%s能给一下吗？", "any %s? "), CL("加个%s可以不，", "%s if you get a sec? "), CL("求求了，%s加一下，", "%s would be great, ") },
        reqFood = { CL("%s来点呗，", "some %s pls? "), CL("能不能给点%s，", "can I get some %s? "), CL("顺手做点%s呗，", "could you toss me some %s? "),
            CL("%s能给一点吗？", "any %s to spare? "), CL("讨点%s，", "spare some %s? "), CL("做点%s可以不，", "some %s if you get a sec? ") },
        done = { CL("谢谢哈", "Thx!"), CL("麻烦了", "Ty!"), CL("感激不尽", "Many thanks!"),
            CL("谢谢你啊", "Thank you so much!"), CL("好人一生平安", "You're a star!"), CL("感谢大佬", "Big thanks!") },
    }
    for k, t in pairs(more) do
        local d = P[k]
        if d then for _, v in ipairs(t) do d[#d + 1] = v end end
    end
    return P
end
function DC.AskTypos()
    return {
        { CL("求个", "could I"), CL("球个", "cuold I") }, { CL("求点", "could I"), CL("球点", "cuold I") },
        { CL("多谢", "Much appreciated"), CL("多些", "Much apreciated") }, { CL("谢啦", "Thanks a lot"), CL("谢拉", "thx a lot") },
        { CL("辛苦啦", "Cheers"), CL("辛苦拉", "cheers") }, { CL("先谢过啦", "Appreciate it"), CL("先谢过拉", "Apreciate it") },
        { CL("感谢感谢", "Thank you"), CL("感谢感写", "Thnak you") }, { CL("谢谢~", "Thanks!"), CL("谢谢谢~", "thx!") },
        { CL("吗？", "please? "), CL("嘛？", "pls? ") }, { CL("方便", "mind"), CL("方面", "mnid") },
        { CL("想要", "would you"), CL("像要", "woudl you") }, { CL("好心的", "Excuse me"), CL("好心滴", "Excuse me") },
        { CL("你好", "Hi there"), CL("你号", "Hi tehre") }, { CL("蹭个", "please"), CL("曾个", "plz") },
        { CL("麻烦", "spare"), CL("麻凡", "sapre") }, { CL("打扰下", "Sorry to bother"), CL("打绕下", "Sory to bother") },
    }
end
function DC.AskTypoOn() return not DC.AskFixed() and not (ns.db and DC.DB().rec.askTypo == false) end
local function rnd(n)
    local ok, v = pcall(math.random, n)
    return (ok and type(v) == "number" and v >= 1 and v <= n) and v or 1
end
local function swap1(s, a, b)
    local i, j = s:find(a, 1, true)
    if not i then return s, false end
    return s:sub(1, i - 1) .. b .. s:sub(j + 1), true
end
-- c = DC.AskCombo 给的这一组；call / req / done = 片段（req 还带 %s）
function DC.Typo(c, call, req, done)
    if type(c) ~= "table" or not DC.AskTypoOn() then return call, req, done end
    if c[4] == nil then c[4] = (rnd(DC.TYPO_P) == 1) and rnd(60) or 0 end
    if c[5] == nil then c[5] = rnd(6) end
    if c[5] == 1 then call = "" end
    if c[5] == 2 then
        done = ""
        if req:sub(-3) == "，" then req = req:sub(1, -4) elseif req:sub(-2) == ", " then req = req:sub(1, -3) end
    end
    local seed = c[4]
    if seed <= 0 then return call, req, done end
    local cand = {}
    for _, t in ipairs(DC.AskTypos()) do
        local a = t[1]
        if a ~= t[2] and (call:find(a, 1, true) or req:find(a, 1, true) or done:find(a, 1, true)) then cand[#cand + 1] = t end
    end
    if #cand == 0 then return call, req, done end
    local t, ok = cand[(seed - 1) % #cand + 1], nil
    call, ok = swap1(call, t[1], t[2]); if ok then return call, req, done end
    req, ok = swap1(req, t[1], t[2]); if ok then return call, req, done end
    return call, req, (swap1(done, t[1], t[2]))
end
