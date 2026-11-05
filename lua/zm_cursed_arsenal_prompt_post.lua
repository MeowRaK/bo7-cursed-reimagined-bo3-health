-- Cursed Reimagined - Arsenal prompt text ("Equip random Ammo Mod")
-- Based on zm_perk_remove_post.lua (Perk Remove - Made by Kazuto): same layout,
-- helpers and native UI timer. zm_cursed_reimagined.gsc (v3.9+) puts the text
-- in the dvar cursed_arsenal_prompt while you are at an Arsenal ("" = hidden).
-- Install: Assets/Lua/ui/zm_cursed_arsenal_prompt_post.lua
-- Position: AR_LEFT / AR_TOP are offsets from screen centre (virtual 1920x1080);
-- AR_LEFT lines the text up with the left edge of the prompt title ("ARSENAL"),
-- AR_TOP puts it on the prompt's description line (same as zm_perk_remove_post.lua).

-- -------------------- SETTINGS --------------------
local AR_LEFT  = -62
local AR_TOP   = 192
local AR_WIDTH = 300
local AR_SIZE  = 16
local AR_RGB   = 0xd2d6dc

-- -------------------- SETUP --------------------
local C=rawget(_G,"CLUA")
local H=rawget(_G,"xhash") or rawget(_G,"PushXHash") or (type(C)=="table" and C.PushXHash)
local HD=rawget(_G,"xhashdvar") or rawget(_G,"PushXHashDvar") or (type(C)=="table" and C.PushXHashDvar)
if type(H)~="function" or type(HD)~="function" then return end
local function cachedHash(native)
    local cache={}
    return function(name)
        local value=cache[name]
        if value==nil then value=native(name);cache[name]=value end
        return value
    end
end
H,HD=cachedHash(H),cachedHash(HD)
local old=rawget(_G,"CursedArsenalPrompt")
if old then old.enabled=false;if old.clear then pcall(old.clear) end end
local S={enabled=true,ticks=0}
rawset(_G,"CursedArsenalPrompt",S)

-- -------------------- HELPERS --------------------
local function get(object,key)
    if object==nil then return nil end
    local plain,value=pcall(function()return object[key]end)
    if plain and value~=nil then return value end
    local ok,hashed=pcall(function()return object[H(key)]end)
    if ok then return hashed end
    return nil
end
local function invoke(object,key,...)
    local f=get(object,key)
    if type(f)=="function" then return f(...) end
end
local function call(object,key,...)
    local f=get(object,key)
    if type(f)=="function" then return f(object,...) end
end
local function read(name)
    local value=invoke(rawget(_G,"Dvar"),"GetDvarString",HD(name))
    if value~=nil then return tostring(value) end
end
local function inMatch()
    return invoke(rawget(_G,"Engine"),"InFrontend")==false
end
local function newElement(kind)
    local f=get(get(rawget(_G,"LUI"),kind),"new")
    if type(f)~="function" then error("Native "..kind.." constructor unavailable",0) end
    return f()
end
local function passive(element)
    call(element,"SetHandleMouse",false);call(element,"setFocusable",false)
end

-- -------------------- DRAWING --------------------
local function clear()
    if S.frame then pcall(call,S.frame,"closeTree") end
    S.frame=nil;S.parent=nil;S.text=nil;S.last=nil;S.visible=false
end
local function hide()
    if S.frame and S.visible then call(S.frame,"SetAlpha",0,0) end
    S.visible=false;S.last=nil
end
local function parentFor(root)
    if type(get(root,"addElement"))~="function" then return nil end
    for _=1,16 do
        local parent=call(root,"getParent")
        if not parent or parent==root then break end
        root=parent
    end
    return root
end
local function displayParent()
    return parentFor(invoke(get(rawget(_G,"LUI"),"UIRoot"),"GetRootForControllerIndex",0))
end

local function build(parent)
    clear()
    local frame=newElement("UIElement")
    call(frame,"SetAlpha",0);call(frame,"setPriority",1000);passive(frame);call(parent,"addElement",frame)

    call(frame,"SetAnchorsAndPosition",.5,.5,.5,.5,AR_LEFT,AR_LEFT+AR_WIDTH,AR_TOP,AR_TOP+AR_SIZE+8)
    local text=newElement("UIStyledText")
    call(text,"SetAnchorsAndPosition",0,1,0,1,0,AR_WIDTH,0,AR_SIZE+6)
    local fonts=rawget(_G,"FONT_HANDLE")
    local font=get(fonts,"SecondaryRegular") or get(fonts,"TertiaryMedium") or get(fonts,"PrimaryRegular")
    if font then call(text,"SetFont",font) end
    call(text,"SetFontSize",AR_SIZE*(tonumber(rawget(_G,"_PT")) or 1))
    call(text,"SetRGB",AR_RGB);call(text,"SetAlignment",0)
    passive(text);call(frame,"addElement",text)
    S.frame=frame;S.parent=parent;S.text=text
end

-- -------------------- UPDATE --------------------
local function tick()
    S.ticks=S.ticks+1
    if not inMatch() then if S.frame then clear() end;return end

    local value=read("cursed_arsenal_prompt") or ""
    if value=="" or invoke(get(rawget(_G,"LUI"),"FlowManager"),"IsInStack",H("MPPauseMenu"))==true then
        hide();return
    end
    local parent=displayParent()
    if not parent then return end
    if not S.frame or S.parent~=parent then build(parent) end
    if value~=S.last then call(S.text,"setText",value);S.last=value end
    if not S.visible then call(S.frame,"SetAlpha",1,0);S.visible=true end
end

-- -------------------- TIMER --------------------
local function timerRoot()
    local L=rawget(_G,"LUI")
    local ok,current=pcall(invoke,L,"GetRoot")
    if ok and current then return current end
    return get(L,"primaryRoot")
end
local function ensureTimer()
    if not S.enabled then return end
    local root=timerRoot()
    if not root then return end
    local okParent,parent=pcall(call,S.timer,"getParent")
    if okParent and parent==root then return end
    if S.timer then pcall(call,S.timer,"closeTree") end
    S.timer=nil
    pcall(function()
        local host=newElement("UIElement")
        passive(host);call(root,"addElement",host);S.timer=host
        local function schedule()
            if not S.enabled or S.timer~=host then return end
            local animation=call(host,"Wait",16)
            if not animation then S.timer=nil;return end
            animation.onComplete=function()
                if not S.enabled or S.timer~=host then return end
                local ok=pcall(tick)
                if not ok then clear() end
                pcall(schedule)
            end
        end
        schedule()
    end)
end
S.ensureTimer=ensureTimer;S.clear=clear

-- -------------------- RESTART --------------------
local installed=setmetatable({},{__mode="k"})
local function install()
    local input=get(rawget(_G,"LUI"),"UIRoot")
    local original=get(input,"QueueInput")
    if type(original)~="function" or installed[input] then return end
    local wrapped=function(...)
        if S.enabled then pcall(ensureTimer) end
        return original(...)
    end
    installed[input]=true
    input.QueueInput=wrapped;input[H("QueueInput")]=wrapped
end
pcall(ensureTimer)
pcall(install)
