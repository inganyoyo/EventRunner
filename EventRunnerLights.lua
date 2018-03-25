--[[
%% properties
55 value
66 value
77 value
%% events
%% globals
counter
--]]

_version = "0.99"

--[[
-- EventRunner. Event based scheduler/device trigger handler
-- Copyright 2018 Jan Gabrielsson. All Rights Reserved.
--]]

_sceneName ="Demo" -- Set to scene/script name
_debugLevel   = 3
_deviceTable  = "deviceTable" -- Name of json struct with configuration data (i.e. "HomeTable")

_HC2 = true
Event = {}
-- If running offline we need our own setTimeout and net.HTTPClient() and other fibaro funs...
if dofile then dofile("EventRunnerDebug.lua") end

---------------- Callbacks to user code --------------------
function main()

  -- Read in devicetable
  local conf = json.decode(fibaro:getGlobalValue(_deviceTable))
  local dev = conf.dev
  Util.reverseMapDef(dev) -- Make device names avilable for debugging

  Rule.define('foo',function(a,b,c) return a+b+c end)
  Rule.eval("%foo(1,2,3)")
  
  -- Set up variables for use in rules
  for k,v in pairs({ 
      td=dev.toilet_down,kt=dev.kitchen,ha=dev.hall,
      lr=dev.livingroom,ba=dev.back,gr=dev.game,
      ti=dev.tim,ma=dev.max,bd=dev.bedroom}) 
  do Util.defvar(k,v) end

-- Kitchen
  Rule.macro('LIGHTTIME',"(day('sat-fri')&hour('8-12')|hour('24-4'))")

  Rule.new([[for(00:10,safe($kt.movement)&$LIGHTTIME$) => off($kt.lamp_table)]])

  fibaro:call(dev.kitchen.lamp_stove, 'turnOn')
  Event:post({type='property', deviceID=dev.kitchen.movement, value=0}, "n09:00")

  Rule.new([[for(00:10,safe([$kt.movement,$lr.movement,$ha.movement])&$LIGHTTIME$) =>
      isOn([$kt.lamp_stove,$kt.lamp_sink,$ha.lamp_hall])&off([$kt.lamp_stove,$kt.lamp_sink,$ha.lamp_hall])&
      log('Turning off kitchen spots after 10 min inactivity')]])

-- Kitchen
  Rule.new("daily(sunset-00:10) => press($kt.sink_led,1),log('Turn on kitchen sink light')")
  Rule.new("daily(sunrise+00:10) => press($kt.sink_led,2),log('Turn off kitchen sink light')")

  Rule.new("daily(sunset-00:10) => on($kt.lamp_table),log('Evening, turn on kitchen table light')")

-- Living room
  Rule.new("daily(sunset-00:10) => on($lr.lamp_window),log('Turn on livingroom light')")
  Rule.new("daily(midnight) => off($lr.lamp_window),log('Turn off livingroom light')")

-- Front
  Rule.new("daily(sunset-00:10) => on($ha.lamp_entrance),log('Turn on lights entr.')")
  Rule.new("daily(sunset) => off($ha.lamp_entrance),log('Turn off lights entr.')")

-- Back
  Rule.new("daily(sunset-00:10) => on($ba.lamp),log('Turn on lights back')")
  Rule.new("daily(sunset) => off($ba.lamp),log('Turn off lights back')")

-- Game room
  Rule.new("daily(sunset-00:10) => on($gr.lamp_window),log('Turn on gaming room light')")
  Rule.new("daily(23:00) => off($gr.lamp_window),log('Turn off gaming room light')")

-- Tim
  Rule.new("daily(sunset-00:10) => on([$ti.bed_led,$ti.lamp_window]),log('Turn on lights for Tim')")
  Rule.new("daily(midnight) => off([$ti.bed_led,$ti.lamp_window]),log('Turn off lights for Tim')")

-- Max
  Rule.new("daily(sunset-00:10) => on($ma.lamp_window),log('Turn on lights for Max')")
  Rule.new("daily(midnight) => off($ma.lamp_window),log('Turn off lights for Max')")

-- Bedroom
  Rule.new("daily(sunset) => on([$bd.lamp_window,$bd.lamp_table,$bd.bed_led]),log('Turn on bedroom light')")
  Rule.new("daily(23:00) => off([$bd.lamp_window,$bd.lamp_table,$bd.bed_led]),log('Turn off bedroom light')")


  Rule.new([[csEvent($lr.lamp_roof_holk)==$S2.click =>
    toggle($lr.lamp_roof_sofa),log('Toggling lamp downstairs')]])

  Rule.new([[csEvent($bd.lamp_roof)==$S2.click =>
    toggle([$bd.lamp_window, $bd.bed_led]),log('Toggling bedroom lights')]])

  Rule.new([[csEvent($ti.lamp_roof)==$S2.click =>
    toggle($ti.bed_led),log('Toggling Tim bedroom lights')]])

  Rule.new([[csEvent($ti.lamp_roof)==$S2.double =>
    toggle($ti.lamp_window),log('Toggling Tim window lights')]])

  Rule.new([[csEvent($ma.lamp_roof)==$S2.click =>
    toggle($ma.lamp_window),log('Toggling Max bedroom lights')]])

  Rule.new([[csEvent($gr.lamp_roof)==$S2.click =>
    toggle($gr.lamp_window),log('Toggling Gameroom window lights')]])

  Rule.new([[csEvent($kt.lamp_table)==$S2.click =>
    if(label($kt.sonos,'lblState')=='Playing',press($kt.sonos,8),press($kt.sonos,7)),
    log('Toggling Sonos %s',label($kt.sonos,'lblState'))]])

  Rule.new([[#property{deviceID=$lr.lamp_window} => 
    if(isOn($lr.lamp_window),[press($lr.lamp_tv,1),press($lr.lamp_globe,1)],[press($lr.lamp_tv,2),press($lr.lamp_globe,1)])]])

  Event:event({type='error'},function(env) local e = env.event 
      Log(LOG.ERROR,"Runtime error %s for '%s' receiving event %s",e.err,e.rule,e.event) 
    end)
end
------------------- EventModel --------------------  
local _supportedEvents = {property=true,global=true,event=true,remote=true}
local _trigger = fibaro:getSourceTrigger()
local _type, _source = _trigger.type, _trigger
local _MAILBOX = "MAILBOX"..__fibaroSceneId

if _type == 'other' and fibaro:args() then
  _trigger,_type = fibaro:args()[1],'remote'
end

if not _FIB then
  _FIB={ get = fibaro.get, getGlobal = fibaro.getGlobal }
end
---------- Producer(s) - Handing over incoming triggers to consumer --------------------
if _supportedEvents[_type] then
  local event = type(_trigger) ~= 'string' and json.encode(_trigger) or _trigger
  local ticket = '<@>'..tostring(source)..event
  repeat 
    while(fibaro:getGlobal(_MAILBOX) ~= "") do fibaro:sleep(100) end -- try again in 100ms
    fibaro:setGlobal(_MAILBOX,ticket) -- try to acquire lock
  until fibaro:getGlobal(_MAILBOX) == ticket -- got lock
  fibaro:setGlobal(_MAILBOX,event) -- write msg
  fibaro:abort() -- and exit
end

---------- Consumer - re-posting incoming triggers as internal events --------------------
fibaro:setGlobal(_MAILBOX,"") -- clear box
local function _poll()
  local l = fibaro:getGlobal(_MAILBOX)
  if l and l ~= "" and l:sub(1,3) ~= '<@>' then -- Something in the mailbox
    fibaro:setGlobal(_MAILBOX,"") -- clear mailbox
    Debug(4,"Incoming event:%",l)
    post(json.decode(l)) -- and post it to our "main()"
  end
  setTimeout(_poll,250) -- check every 250ms
end

------------------------ Support functions -----------------
LOG = {WELCOME = "orange",DEBUG = "white", SYSTEM = "Cyan", LOG = "green", ERROR = "Tomato"}
_format = string.format

if _HC2 then -- if running on the HC2
  function _Msg(level,color,message,...)
    if (_debugLevel >= level) then
      local args = type(... or 42) == 'function' and {(...)()} or {...}
      local tadj = _timeAdjust > 0 and osDate("(%X) ") or ""
      local m = _format('<span style="color:%s;">%s%s</span><br>', color, tadj, _format(message,table.unpack(args)))
      fibaro:debug(m) return m
    end
  end
  if not _timeAdjust then _timeAdjust = 0 end -- support for adjusting for hw time drift on HC2
  osTime = function(arg) return arg and os.time(arg) or os.time()+_timeAdjust end
  osClock = os.clock
  function _setClock(_) end
end

function Debug(level,message,...) _Msg(level,LOG.DEBUG,message,...) end
function Log(color,message,...) return _Msg(-100,color,message,...) end
function osDate(f,t) t = t or osTime() return os.date(f,t) end
function errThrow(m,err) if type(err) == 'table' then table.insert(err,1,m) else err = {m,err} end error(err) end
function _assert(test,msg,...) if not test then msg = _format(msg,...) error({msg},3) end end
function _assertf(test,msg,fun) if not test then msg = _format(msg,fun and fun() or "") error({msg},3) end end
function isTimer(t) return type(t) == 'table' and t[Event.TIMER] end
function isRule(r) return type(r) == 'table' and r[Event.RULE] end
function isEvent(e) return type(e) == 'table' and e.type end
function _transform(obj,tf)
  if type(obj) == 'table' then
    local res = {} for l,v in pairs(obj) do res[l] = _transform(v,tf) end 
    return res
  else return tf(obj) end
end
function _copy(obj) return _transform(obj, function(o) return o end) end
function _equal(e1,e2)
  local t1,t2 = type(e1),type(e2)
  if t1 ~= t2 then return false end
  if t1 ~= 'table' and t2 ~= 'table' then return e1 == e2 end
  for k1,v1 in pairs(e1) do if e2[k1] == nil or not _equal(v1,e2[k1]) then return false end end
  for k2,v2 in pairs(e2) do if e1[k2] == nil or not _equal(e1[k2],v2) then return false end end
  return true
end
---------------------- Event/rules handler ----------------------
Event = Event or {}
Event.BREAK, Event.TIMER, Event.RULE ='%%BREAK%%', '%%TIMER%%', '%%RULE%%'

function Event:post(e,time) -- time in 'toTime' format, see below.
  _assert(isEvent(e) or type(e) == 'function', "Bad event format")
  time = toTime(time or osTime())
  if time < osTime() then return nil end
  if type(e) == 'function' then return {[Event.TIMER]=setTimeout(e,1000*(time-osTime()))} end
  if _debugLevel >= 3 and not e._sh then Debug(3,"Posting %s for %s",function() return Util.prettyJson(e),osDate("%a %b %d %X",time) end) end
  return {[Event.TIMER]=setTimeout(function() _handleEvent(e) end,1000*(time-osTime()))}
end

function Event:cancel(t)
  _assert(isTimer(t) or t == nil,"Bad timer")
  if t then clearTimeout(t[Event.TIMER]) end 
  return nil 
end

function Event:enable(r) _assert(isRule(r), "Bad event format") r.enable() end
function Event:disable(r) _assert(isRule(r), "Bad event format") r.disable() end

function Event:postRemote(sceneID, e) -- Post event to other scenes
  _assert(isEvent(e), "Bad event format")
  e._from = __fibaroSceneId
  fibaro:startScene(sceneID,{json.encode(e)})
end

_getProp = {}
_getProp['property'] = function(e,v2)
  e.propertyName = e.propertyName or 'value'
  local v,t = _FIB:get(e.deviceID,e.propertyName,true)
  e.value = v2 or v return t
end
_getProp['global'] = function(e,v2) local v,t = _FIB:getGlobal(e.name,true) e.value = v2 or v return t end

_rules = {}

-- e=event, a=action
function Event:event(e,action) -- define rules - event template + action
  _assert(isEvent(e), "bad event format '%s'",Util.prettyJson(e))
  action = _compileAction(action)
  e = _compilePattern(e)
  _rules[e.type] = _rules[e.type] or {}
  local rules = _rules[e.type]
  local rule,fn = {[Event.RULE]=e, action=action, org=Util.prettyJson(args)}, true
  for _,rs in ipairs(rules) do -- Collect handlers with identical events. {{e1,e2,e3},{e1,e2,e3}}
    if _equal(e,rs[1][Event.RULE]) then rs[#rs+1] = rule fn = false break end
  end
  if fn then rules[#rules+1] = {rule} end
  rule.enable = function() rule._disabled = nil return rule end
  rule.disable = function() rule._disabled = true return rule end
  return rule
end

-- t=time, a=action, c=cond, s=start
function Event:schedule(time,action,opt)
  local test, start = opt and opt.cond, opt and opt.start or false
  local loop,tp = {type='_scheduler'..tostring(args), _sh=true}
  local test2,action2 = _compileAction(test),_compileAction(action)
  local re = Event:event(loop,function(env)
      local fl = test == nil or test2()
      if fl == Event.BREAK then return
      elseif fl then action2() end
      tp = Event:post(loop, time) 
    end)
  local res = {
    [Event.RULE] = {},
    enable = function() if not tp then tp = Event:post(loop,start and 0 or time) end return res end, 
    disable= function() tp = Event:cancel(tp) return res end, 
  }
  res.enable()
  return res
end

_compiledExpr = {}
_compiledScript = {}
_compiledCode = {}
function _compileAction(a)
  local function assoc(a,f,table) table[f] = a; return f end
  if type(a) == 'function' then return a end
  if isEvent(a) then return function(e) return Event:post(a) end end  -- Event -> post(event)
  if type(a) == 'string' then                  -- Assume 'string' expression...
    a = assoc(a,ScriptCompiler.parse(a),_compiledExpr) -- ...compile Expr to script 
  end
  a = assoc(a,ScriptCompiler.compile(a),_compiledScript)
  return assoc(a,function(e) Util.defvar('env',e) return ScriptEngine.eval(a) end,_compiledCode)
end

function _invokeRule(env)
  local status, res = pcall(function() env.rule.action(env) end) -- call the associated action
  if not status then
    res = type(res)=='table' and table.concat(res,' ') or res
    Event:post({type='error',err=res,rule=env.rule.org,event=Util.prettyJson(env.event),_sh=true})    -- Send error back
    env.rule._disabled = true                            -- disable rule to not generate more errors
  end
end

-- {{e1,e2,e3},{e4,e5,e6}}
function _handleEvent(e) -- running a posted event
  if _OFFLINE and not _REMOTE then if _simFuns[e.type] then _simFuns[e.type](e)  end end
  local env = {event = e}
  if _getProp[e.type] then _getProp[e.type](e,e.value) end  -- patch events
  for _,rules in ipairs(_rules[e.type] or {}) do -- Check all rules of 'type'
    if _match(rules[1][Event.RULE],e) then
      for _,rule in ipairs(rules) do 
        if not rule._disabled then env.rule = rule; _invokeRule(env) end
      end
    end
  end
end

function _coerce(x,y)
  local x1 = tonumber(x) if x1 then return x1,tonumber(y) else return x,y end
end

_constraints = {}
_constraints['=='] = function(val) return function(x) x,val=_coerce(x,val) return x == val end end
_constraints['>='] = function(val) return function(x) x,val=_coerce(x,val) return x >= val end end
_constraints['<='] = function(val) return function(x) x,val=_coerce(x,val) return x <= val end end
_constraints['>'] = function(val) return function(x) x,val=_coerce(x,val) return x > val end end
_constraints['<'] = function(val) return function(x) x,val=_coerce(x,val) return x < val end end
_constraints['~='] = function(val) return function(x) x,val=_coerce(x,val) return x ~= val end end
_constraints[''] = function(val) return function(x) return x ~= nil end end

function _compilePattern(obj) 
  return _transform(obj, function(o) 
      if type(o) == 'string' and o:sub(1,1) == '$' then
        local op,val = o:match("$([<>=~]*)([+-]?%d*%.?%d*)")
        local c = _constraints[op](tonumber(val) or val)
        return {_constr=c, _str=o}
      else return o end
    end) 
end

function _match(pattern,expr) -- match 2 key-pair event structures
  if pattern == expr then return true end
  if type(pattern) == 'table' then
    if pattern._constr then return pattern._constr(expr)
    elseif type(expr) == 'table' then
      for k,v in pairs(pattern) do 
        if not _match(v,expr[k]) then return false end 
      end
      return true
    end
  end 
  return false
end

---------------- Time functions --------------------------
function hm2sec(hmstr)
  local offs,sun = 0
  sun,offs = hmstr:match("^(%a+)([+-]?%d*)")
  if sun and (sun == 'sunset' or sun == 'sunrise') then
    hmstr,offs = fibaro:getValue(1,sun.."Hour"), tonumber(offs) or 0
  end
  local h,m,s = hmstr:match("(%d+):(%d+):?(%d*)")
  _assert(h and m,"Bad hm2sec string %s",hmstr)
  return h*3600+m*60+(tonumber(s) or 0)+(offs or 0)*60
end

function midnight()
  local t = osDate("*t")
  t.hour,t.min,t.sec = 0,0,0
  return osTime(t)
end

function today(s) 
  local m = midnight()
  return m+s 
end

function between(t1,t2)
  local tn = osTime()
  t1,t2 = today(hm2sec(t1)),today(hm2sec(t2))
  if t1 <= t2 then return t1 <= tn and tn <= t2 else return tn <= t1 or tn >= t2 end 
end

-- toTime("10:00") -> 10*3600+0*60s     
-- toTime("10:00:05") -> 10*3600+0*60+5*1s  
-- toTime("a10:00") -> (a)bsolute time. 10AM today. midnight+10*3600+0*60s 
-- toTime("n10:00") -> (n)ext time. today at 10.00AM if called before (or at) 10.00AM else 10:00AM next day
-- toTime("r10:00") -> (r)elative time. os.time() + 10 hours
-- toTime("r00:01:22") -> (r)elative time. os.time() + 1min and 22sec
-- toTime("sunset") -> todays sunset
-- toTime("sunrise") -> todays sunset
-- toTime("sunset+10") -> todays sunset + 10min. E.g. sunset="05:10", =>toTime("05:10")+10*60
-- toTime("sunrise-5") -> todays sunrise - 5min
function toTime(time)
  if type(time) == 'number' then return time end
  local p = time:sub(1,1)
  if p == 'r' then return hm2sec(time:sub(2))+osTime()
  elseif p == 'n' then
    local t1,t2 = today(hm2sec(time:sub(2))),osTime()
    return t1 > t2 and t1 or t1+24*60*60
  elseif p == 'a' then return  hm2sec(time:sub(2))+midnight()
  else return hm2sec(time)
  end
end

--------- Script ------------------------------------------
Util = Util or {}

function newScriptEngine()
  local self = {}

  local timeFs ={["*"]=function(t) return t end,
    a=function(t) return t+midnight() end,
    r=function(t) return t+osTime() end,
    n=function(t) t=t+midnight() return t<= osTime() and t or t+24*60*60 end,
    ['midnight']=function(t) return midnight() end,
    ['sunset']=function(t) return hm2sec('sunset') end,
    ['sunrise']=function(t) return hm2sec('sunrise') end,
    ['now']=function(t) return osTime()-midnight() end}

  function ID(id,i) _assert(tonumber(id),"bad deviceID '%s' for '%s'",id,i[1]) return id end
  local function doit(m,f,s) if type(s) == 'table' then return m(f,s) else return f(s) end end
  local instr,funs,cinstr = {},{},{}
  instr['const'] = function(s,n,a) s.push(a) end
  instr['<time>'] = function(s,n,f,env,i) s.push(timeFs[f](i[4])) end 
  instr['table'] = function(s,n,k,i) local t = {} for j=n,1,-1 do t[k[j]] = s.pop() end s.push(t) end
  instr['array'] = function(s,n) local t = {} for i=n,1,-1 do t[i] = s.pop() end s.push(t) end
  instr['pop'] = function(s,n) s.pop() end
  instr['setL'] = function(s,n,a) Util.setVar(a,s.ref(0)) end
  instr['setG'] = function(s,n,a) fibaro:setGlobal(a[2],tostring(s.ref(0))) end
  instr['jmp'] = function(s,n,a) return a end
  instr['ifnskip'] = function(s,n,a,i) if not s.ref(0) then return a end end
  instr['ifskip'] = function(s,n,a,i) if s.ref(0) then return a end end
  instr['yield'] = function(s,n) error({type='yield'}) end
  instr['not'] = function(s,n) s.push(not s.pop()) end
  instr['.'] = function(s,n) local k,table = s.pop(),s.pop() s.push(table[k]) end
  instr['+'] = function(s,n) s.push(s.pop()+s.pop()) end
  instr['-'] = function(s,n) s.push(-s.pop()+s.pop()) end
  instr['*'] = function(s,n) s.push(s.pop()*s.pop()) end
  instr['/'] = function(s,n) s.push(1/s.pop()/s.pop()) end
  instr['>'] = function(s,n) s.push(tostring(s.pop())<tostring(s.pop())) end
  instr['<'] = function(s,n) s.push(tostring(s.pop())>tostring(s.pop())) end
  instr['>='] = function(s,n) s.push(tostring(s.pop())<=tostring(s.pop())) end
  instr['<='] = function(s,n) s.push(tostring(s.pop())>=tostring(s.pop())) end
  instr['~='] = function(s,n) s.push(tostring(s.pop())~=tostring(s.pop())) end
  instr['=='] = function(s,n) s.push(s.pop()==s.pop()) end
  instr['progn'] = function(s,n) local r = s.pop();  s.pop(n-1); s.push(r) end
  instr['log'] = function(s,n) s.push(Log(LOG.LOG,table.unpack(s.lift(n)))) end
  instr['print'] = function(s,n) print(s.ref(0)) end
  instr['tjson'] = function(s,n) local t = s.pop() s.push(Util.prettyJson(t)) end
  instr['osdate'] = function(s,n)
    local x,y = s.ref(n-1), n>1 and s.pop() 
    s.pop(); s.push(os.date(x,y))
  end
  instr['daily'] = function(s,n,a,e) for i=1,n do s.pop() end s.push(true) end
  instr['ostime'] = function(s,n) s.push(osTime()) end
  instr['frm'] = function(s,n) s.push(string.format(table.unpack(s.lift(n)))) end
  instr['var'] = function(s,n,a) s.push(Util.getVar(a)) end
  instr['glob'] = function(s,n,a) s.push(fibaro:getGlobal(a)) end
  instr['on'] = function(s,n,a,e,i) doit(Util.mapF,function(id) fibaro:call(ID(id,i),'turnOn') end,s.pop()) s.push(true) end
  instr['isOn'] = function(s,n,a,e,i) s.push(doit(Util.mapOr,function(id) return fibaro:getValue(ID(id,i),'value') > '0' end,s.pop())) end
  instr['off'] = function(s,n,a,e,i) doit(Util.mapF,function(id) fibaro:call(ID(id,i),'turnOff') end,s.pop()) s.push(true) end
  instr['isOff'] = function(s,n,a,e,i) s.push(doit(Util.mapAnd,function(id) return fibaro:getValue(ID(id,i),'value') == '0' end,s.pop())) end
  instr['toggle'] = function(s,n,a,e,i)
    s.push(doIt(Util.mapF,function(id) local t = fibaro:getValue(ID(id,i),'value') fibaro:call(id,t>'0' and 'turnOff' or 'turnOn') end,s.pop()))
  end
  instr['power'] = function(s,n,a,e,i) s.push(fibaro:getValue(ID(s.pop(),i),'value')) end
  instr['lux'] = instr['power'] instr['temp'] = instr['power'] instr['sense'] = instr['power']
  instr['value'] = instr['power']
  instr['send'] = function(s,n,a,e,i) local m,id = s.pop(), ID(s.pop(),i) fibaro:call(id,'sendPush',m) s.push(m) end
  instr['press'] = function(s,n,a,e,i) local key,id = s.pop(),ID(s.pop(),i) fibaro:call(id,'pressButton', key) end
  instr['scene'] = function(s,n,a,e,i) s.push(fibaro:getValue(CS(s.pop(),i),'sceneActivation')) end
  instr['once'] = function(s,n,a,e,i) local f; i[4],f = s.pop(),i[4]; s.push(not f and i[4]) end
  instr['post'] = function(s,n) local e,t=s.pop(),nil; if n==2 then t=e; e=s.pop() end Event:post(e,t) s.push(e) end
  instr['safe'] = instr['isOff'] 
  instr['betw'] = function(s,n) local t2,t1,now=s.pop(),s.pop(),osTime()-midnight()
    if t1<=t2 then s.push(t1 <= now and now <= t2) else s.push(now >= t1 or now <= t2) end 
  end
  instr['fun'] = function(s,n) local a,f=s.pop(),s.pop() _assert(funs[f],"undefined fun '%s'",f) s.push(funs[f](table.unpack(a))) end
  instr['repeat'] = function(s,n,a,e) 
    local v,c = n>0 and s.pop() or math.huge
    if not e.forR then s.push(0) 
    elseif v > e.forR[2] then s.push(e.forR[1]()) else s.push(e.forR[2]) end 
  end
  instr['for'] = function(s,n,a,e,i) 
    local val,time = s.pop(),s.pop()
    e.forR = nil
    if i[6] then
      i[6] = nil; 
      if val then
        i[7] = (i[7] or 0)+1
        e.forR={function() Event:post(function() i[6] = true; i[5] = nil; self.eval(e.o,e) end,time+osTime()) return i[7] end,i[7]}
      end
      s.push(val) 
      return
    end 
    i[7] = 0
    if i[5] and (not val) then i[5] = Event:cancel(i[5]) Log(LOG.LOG,"Killing timer")-- Timer already running, and false, stop timer
    elseif (not i[5]) and val then                        -- Timer not running, and true, start timer
      i[5]=Event:post(function() i[6] = true; i[5] = nil; self.eval(e.o,e) end,time+osTime()) 
    end
    s.push(false)
  end
  for k,_ in pairs(instr) do cinstr[k]=1 end
  for k,i in pairs({['for']=2,fun=2,betw=2,post=-2,press=2,send=2,sunset=0,sunrise=0,
      frm=-1,log=-10,daily=-50,array=-50,table=-50}) do cinstr[k]=i end
  
  function self._setInstrs(f) local s = instr; instr = f; return s end

  function self.defineInstr(name,fun) 
    _assert(instr[name] == nil,"Instr already defined: %s",name) 
    instr[name] = fun
  end
  function self.define(name,fun) 
    _assert(funs[name] == nil,"Function already defined: %s",name) 
    funs[name] = fun
  end

  function self.eval(o,e) o.stack.reset(); o.p=1; o.e = e or {}; return self.continue(o) end 
  function self.continue(o)
    local code,stack,p,env,i = o.code,o.stack,o.p,o.e
    env.o = o
    local status, res = pcall(function()  
        while p <= #code do
          i = code[p]
          local res = instr[i[1]](stack,i[2],i[3],env,i)
          p = p+(res or 1)
        end
        return {type='value', value=stack.pop()} 
      end)
    if status then return res
    else
      if not instr[i[1]] then errThrow("eval","undefined function "..i[1]) end
      if type(res) == 'table' and res.type == 'yield' then
        o.p = p+1
        return {type='suspended', value='yield'}
      end
      error(res)
    end
  end
  return self
end
ScriptEngine = newScriptEngine()

function newScriptCompiler()
  local self = {}

  local function mkOp(o) return o end
  local POP = {mkOp('pop'),0}

  local _comp = {}
  function self._getComps() return _comp end

  local function compT(e,ops)
    local json = Util.prettyJson
    if type(e) == 'table' then
      local ef = e[1]
      if _comp[ef] then _comp[ef](e,ops)
      elseif ef == 'set' then
        local var,expr = e[2], e[3]
        local instr = var[1] == 'var' and 'setL' or 'setG'
        compT(expr,ops)
        ops[#ops+1] = {mkOp(instr),1,var}
      elseif ef == 'table' then
        local keys = {}
        for i=2,#e do keys[#keys+1] = e[i][2]; compT(e[i][3],ops) end
        ops[#ops+1]={mkOp('table'),#keys,keys}
      else
        for i=2,#e do compT(e[i],ops) end
        ops[#ops+1] = {mkOp(e[1]),#e-1}
      end
    else ops[#ops+1]={mkOp('const'),1,e} end
  end

  _comp['quote'] = function(e,ops) ops[#ops+1] = {mkOp('const'),1,e[2]} end
  _comp['<time>'] = function(e,ops) ops[#ops+1] = {mkOp('<time>'),2,e[2],e[3]} end
  _comp['var'] = function(e,ops) ops[#ops+1] = {mkOp('var'),1,e} end
  _comp['glob'] = function(e,ops) ops[#ops+1] = {mkOp('glob'),1,e[2]} end
  _comp['%glob'] = function(e,ops) ops[#ops+1] = {mkOp('%glob'),1,e[2]} end
  _comp['and'] = function(e,ops) 
    compT(e[2],ops)
    local o1,z = {mkOp('ifnskip'),0,0}
    ops[#ops+1] = o1 -- true skip 
    z = #ops; ops[#ops+1]= POP; compT(e[3],ops); o1[3] = #ops-z+1
  end
  _comp['=>'] = _comp['and']
  _comp['or'] = function(e,ops)  
    compT(e[2],ops)
    local o1,z = {mkOp('ifskip'),0,0}
    ops[#ops+1] = o1 -- true skip 
    z = #ops; ops[#ops+1]= POP; compT(e[3],ops); o1[3] = #ops-z+1;
  end
  _comp['%NULL'] = function(e,ops) compT(e[2],ops); ops[#ops+1]= POP; compT(e[3],ops) end

  local function mkStack()
    local self,stack,stackp = {},{},0
    function self.push(e) stackp=stackp+1; stack[stackp] = e end
    function self.pop(n) n = n or 1; stackp=stackp-n; return stack[stackp+n] end
    function self.ref(n) return stack[stackp-n] end
    function self.lift(n) local s = {} for i=1,n do s[i] = stack[stackp-n+i] end self.pop(n) return s end
    function self.reset() stackp=0 end
    function self.isEmpty() return stackp==0 end
    return self
  end

  function self.dump(o)
    for p = 1,#o.code do
      local i = o.code[p]
      Log(LOG.LOG,"%-20s",Util.prettyJson(i))
    end
  end

  function self.compile(e) local o = {} compT(e,o) return {code=o,stack=mkStack(),p=1} end

  local _prec = {
    ['*'] = 10, ['/'] = 10, ['.'] = 11, ['+'] = 9, ['-'] = 9, ['{'] = 3, ['['] = 2, ['('] = 1, ['=>'] = 0,
    ['>']=7, ['<']=7, ['>=']=7, ['<=']=7, ['==']=7, ['&']=6, ['|']=5, ['=']=4}
  local _opMap = {['&']='and',['|']='or',['=']='set'}
  local function mapOp(op) return _opMap[op] or op end

  local _tokens = {
    {"^[%s%c]*(%b'')",'string'},
    {"^[%s%c]*%#([0-9a-zA-Z]+)%{",'event'},
    {"^[%s%c]*$([_0-9a-zA-Z\\$\\.]+)",'lvar'},
    {"^[%s%c]*!([_0-9a-zA-Z\\$\\.]+)",'gvar'},
    {"^[%s%c]*([arn]?%d%d:%d%d:?%d*)",'time'},
    {"^[%s%c]*([a-zA-Z][0-9a-zA-Z]*)%(",'call'},
    {"^[%s%c]*%%([a-zA-Z][0-9a-zA-Z]*)%(",'fun'},
    {"^[%s%c]*([%[%]%(%)%{%},])",'spec'},
    {"^[%s%c]*(=>)",'op'},
    {"^[%s%c]*([a-zA-Z][0-9a-zA-Z]*)",'symbol'},
    {"^[%s%c]*(%d+)",'num'},    
    {"^[%s%c]*(%.)",'op'},
    {"^[%s%c]*([%*%+%-/=><&%|]+)",'op'},
  }

  local _specs = { 
    ['('] = {0,'lpar','rpar'},[')'] = {0,'rpar','lpar'},
    ['['] = {0,'array','rbrack'},[']'] = {0,'rbrack','lbrack'},
    ['{'] = {0,'table','rcurl'},['}'] = {0,'rcurl','lcurl'},
    [','] = {0,'comma'}}

  local function tokenize(s) 
    local i,tkns,s1 = 1,{}
    repeat
      s1 = s
      s = s:gsub(_tokens[i][1],
        function(m) local to = _tokens[i] if to[2] == 'spec' then to = _specs[m] end
        tkns[#tkns+1] = {t=to[2], v=m, m=to[3]} i = 1 return "" end)
      if s1 == s then i = i+1 if i > #_tokens then error({_format("bad token '%s'",s)}) end end
    until s:match("^[%s%c]*$")
    self.st = tkns; self.tp = 1 
  end

  local function peekToken() return self.st[self.tp] end
  local function nxtToken() local r = peekToken(); self.tp = self.tp + 1; return r end

  function checkBrackets(s)
    local m = ({lcurl=')', lbrack=']', lpar=')'})[s.t]
    return m and error({_format("missing '%s'",m)}) or s
  end
  local symbol={}
  symbol['true'] = function() return true end
  symbol['false'] = function() return false end
  symbol['nil'] = function() return nil end
  symbol['sunset'] = function() return {'sunset'} end
  symbol['sunrise'] = function() return {'sunrise'} end
  symbol['now'] = function() return {'<time>','now',0} end
  symbol['sunrise'] = function() return {'<time>','sunrise',0} end
  symbol['sunset'] = function() return {'<time>','sunset',0} end
  symbol['midnight'] = function() return {'<time>','midnight',0} end

  function self.expr()
    local st,stp,res,rp = {},0,{},0
    local function notEmpty() return stp > 0 end  
    local function peek() return stp > 0 and st[stp] or nil end
    local function pop() local r = peek(); stp = stp > 0 and stp-1 or stp; return r end
    local function push(t) stp=stp+1; st[stp] = t end
    local function add(t) rp=rp+1; res[rp] = t end
    while true do
      local t = peekToken()
      if t == nil or t.t == 'token' then 
        while notEmpty() do 
          res[rp-1] = {mapOp(checkBrackets(pop()).v),res[rp-1],res[rp]}; rp=rp-1 
        end
        res[rp+1] = nil
        return res
      end
      nxtToken()
      if t.t == 'lvar' then add(Util.v(t.v))
      elseif t.t == 'gvar' then add({'glob',t.v}) 
      elseif t.t == 'num' then add(tonumber(t.v))
      elseif t.t == 'string' then add(t.v:match("^'(.*)'$"))
      elseif t.t == 'symbol' then 
        if symbol[t.v] then add(symbol[t.v]()) else add(t.v) end
      elseif t.t == 'time' then 
        local p,h,m,s = t.v:match("([arn]?)(%d%d):(%d%d):?(%d*)")
        add({'<time>',p == "" and '*' or p,h*3600+m*60+(s~="" and s or 0)})
      elseif t.t == 'array' then
        push({t='call',v='array'})
        push({t='lbrack',v='[',m='rbrack'})
        add('call')
      elseif t.t == 'table' then
        push({t='call',v='table'})
        push({t='lcurl',v='[',m='rcurl'})
        add('call')
      elseif t.t == 'event' then
        push({t='call',v='table'})
        push({t='lcurl',v='{',m='rcurl'})
        add('call')
        if t.v ~= "" then add({'set','type',t.v}) end
      elseif t.t == 'call' or t.t == 'fun' then
        push(t)
        push({t='lpar',v='('})
        add(t.t) -- call or fun
      elseif t.t == 'lpar' then
        push(t)
      elseif t.t == 'rpar' or t.t == 'rcurl' or t.t == 'rbrack' or t.t == 'comma' then
        local op = pop()
        while op and op.t ~= 'lpar' and op.t ~= 'lcurl' and op.t ~= 'lbrack' do
          res[rp-1] = {mapOp(op.v),res[rp-1],res[rp]}; rp = rp-1
          op = pop()
        end
        if op == nil then error({"bad expression"}) end
        if t.t == 'comma' then push(op) elseif t.m ~= op.t then error({"mismatched "..t.m}) end
        if notEmpty() and (peek().t == 'call' or peek().t == 'fun') then
          local f,args = pop(),{}
          while res[rp] ~= 'call' and res[rp] ~= 'fun' do table.insert(args,1,res[rp]); rp=rp-1 end
          if f.v == 'if' then
            res[rp] = {'and',args[1],args[2]}
            if #args == 3 then res[rp] = {'or',res[rp],args[3]} end
          else 
            if f.t == 'call' then res[rp] = {f.v,table.unpack(args)} 
            else res[rp] = {'fun',f.v,{'array',table.unpack(args)}} end
          end
        end
      else
        while notEmpty() and _prec[peek().v] >= _prec[t.v] do
          res[rp-1] = {mapOp(pop().v), res[rp-1], res[rp]}; rp=rp-1
        end
        push(t)
      end
    end
  end

  function self.parse(s)
    tokenize(s)
    local status, res = pcall(function() 
        local expr,expr2,p = self.expr(),{},1
        while expr[p] do expr2[p] = expr[p] p=p+1 end
        if #expr2 > 1 then table.insert(expr2,1,'progn') else expr2 = expr2[1] end
        return expr2
      end)
    if status then return res 
    else 
      res = type(res) == 'string' and {res} or res
      errThrow(_format(" parsing '%s'",s),res)
    end
  end

  return self
end
ScriptCompiler = newScriptCompiler()

function newRuleCompiler()
  local self = {}
  local _dailys = {}
  local _macros = {}
  local function mkID(id) return {type='property', deviceID=id} end

  local mtr={isOn=1,isOff=1,power=1,bat=1,lux=1,safe=1,sense=1,value=1,temp=1,scene=1,['for']=2,once=2,daily=2,glob=2,['.']=2}
  local function regIdFun(s,n,a,e) local d = s.pop() 
    if type(d) == 'table' then Util.mapF(function(i) e.id[i]=mkID end,d) else e.id[d]=mkID end 
    s.push(true) 
  end
  local function skipFun(s,n) s.pop(n) s.push(true) end
  local comps = ScriptCompiler._getComps()
  local andComp, orComp, nullComp = comps['and'],comps['or'],comps['%NULL']
  local oldInstr,newInstr=ScriptEngine._setInstrs(),{}
  for n,f in pairs(oldInstr) do if mtr[n]==1 then newInstr['%'..n] = regIdFun end newInstr[n] = f end
  newInstr['%daily'] = function(s,n,a,e) for i=1,n do e.time[s.pop()]=true end s.push(true) end
  newInstr['%glob'] = function(s,n,a,e) e.glob[n] = true s.push('true') end
  newInstr['%for'],newInstr['%once'],newInstr['%.'] = skipFun,skipFun,skipFun
  ScriptEngine._setInstrs(newInstr)

  function self.define(name,fun) ScriptEngine.define(name,fun) end
  
  function self.defineTrigger(name,code,ftr)
    local instrs = ScriptEngine._setInstrs()
    instrs[name],instrs['%'..name] = code,ftr
    mtr[name]=1
    ScriptEngine._setInstrs(instrs)
  end  

  local function flattenTrigger(expr)
    if type(expr) == 'table' and #expr>0 then
      local op = mtr[expr[1]] and '%'..expr[1] or expr[1]
      if not ({glob=true,var=true,const=true})[op] then
        local res = {op}
        for i=2,#expr do res[#res+1] = flattenTrigger(expr[i]) end
        return res
      else return expr end
    else return expr end 
  end

  local function compTrigger(p) -- Idea, we substitute funcs to make a
    local env = {id={},glob={},time={}}
    local rp = flattenTrigger(p)
    comps['and'],comps['=>'],comps['or'] = nullComp,nullComp,nullComp
    local trigger = ScriptCompiler.compile(rp)
    --ScriptCompiler.dump(trigger)
    comps['and'],comps['=>'],comps['or'] = andComp,andComp,orComp
    ScriptEngine.eval(trigger,env)
    return trigger,env
  end
  local rCounter=0
  
  function self.new(expro)
    expro = self.macroSubs(expro)
    local expr = expro:gsub("(=>)","=> progn(")
    expr = expr..")"
    local e = ScriptCompiler.parse(expr)
    local p,a,res = e[2],e[3]
    _assert(e[1] == '=>',"no '=>' in rule '%s'",expr)
    if expr:match("^%s*#") then
      local ep = ScriptCompiler.compile(p)
      res = Event:event(ScriptEngine.eval(ep).value,a)
    elseif type(p) == 'table' then
      local trigger,env = compTrigger(p)
      local action = _compileAction(expr)
      if next(env.time) then 
        env.id,env.glob,m,ot={},{},midnight(),osTime()
        _dailys[#_dailys+1]={trigger=trigger,action=action}
        for i,t in pairs(env.time) do if i+m > ot then Event:post(action,i+m) end end
      elseif next(env.id) or next(env.glob) then
        for i,f in pairs(env.id) do Event:event(f(i),action).org=expro end
        for i,_ in pairs(env.glob) do Event:event({type='global', name=i},action).org=expro end
      else
        error(_format("no triggers found in rule '%s'",expro))
      end
      local function fl(h) local r={} for k,_ in pairs(h) do r[#r+1]=k end return r end
      res = {[Event.RULE]={time=fl(env.time),device=fl(env.id),global=fl(env.glob)}, action=action}
    else error(_format("rule syntax:'%s'",expro)) end
    rCounter=rCounter+1
    Log(LOG.SYSTEM,"Rule:%s:%.40s",rCounter,expro:match("([^%c]*)"))
    res.org=expro
    return res
  end

  function self.eval(expr)
    expr = self.macroSubs(expr)
    local res=ScriptCompiler.parse(expr)
    --Log(LOG.LOG,Util.prettyJson(res))
    res = ScriptCompiler.compile(res)
    --ScriptCompiler.dump(res)
    res = ScriptEngine.eval(res).value
    Log(LOG.LOG,"%s = %s",expr,Util.prettyJson(res))
  end

  local function errWrap(fun,msg)
    return function(expr) 
      local status, res = pcall(function() return fun(expr) end)
      if status then return res end
      errThrow(_format(msg,expr),res)
    end
  end  
  self.eval=errWrap(self.eval,"while evaluating '%s'")
  self.new=errWrap(self.new,"Rule.new('%s'):")

  function self.macro(name,str) _macros['%$'..name..'%$'] = str end
  function self.macroSubs(str)
    for m,s in pairs(_macros) do str = str:gsub(m,s) end
    return str
  end

  Event:schedule("n00:00",function(env)  -- Scheduler that every night posts 'daily' rules
      local midnight = midnight()
      for _,e in ipairs(_dailys) do
        local env = {id={},glob={},time={}}
        ScriptEngine.eval(e.trigger,env)
        for t,_ in pairs(env.time) do 
          Event:post(e.action,midnight+t) 
        end
      end
    end)
  return self
end

------ Util ----------

function Util.dateTest(dateStr)
  local self = {}
  local days = {sun=1,mon=2,tue=3,wed=4,thu=5,fri=6,sat=7}
  local months = {jan=1,feb=2,mar=3,apr=4,may=5,jun=6,jul=7,aug=8,sep=9,oct=10,nov=11,dec=12}
  local last = {31,28,31,30,31,30,31,31,30,31,30,31}

  local function seq2map(seq) local s = {} for i,v in ipairs(seq) do s[v] = true end return s; end

  local function flatten(seq,res) -- flattens a table of tables
    res = res or {}
    if type(seq) == 'table' then for _,v1 in ipairs(seq) do flatten(v1,res) end else res[#res+1] = seq end
    return res
  end

  local function expandCron(w1)
    local function resolve(id)
      return type(id) == 'number' and id or days[id] or months[id] or tonumber(id)
    end
    local w,m = w1[1],w1[2];
    start,stop = w:match("(%w+)%p(%w+)")
    if (start == nil) then return resolve(w) end
    start,stop = resolve(start), resolve(stop)
    local res = {}
    if (string.find(w,"/")) then -- 10/2
      while(start < m.max) do
        res[#res+1] = start
        start = start+stop
      end
    else 
      while (start ~= stop) do -- 10-2
        res[#res+1] = start
        start = start+1; if start>m.max then start=m.min end  
      end
      res[#res+1] = stop
    end
    return res
  end

  local seq = split(dateStr," ")   -- day,month,wday
  local fd = seq[1]:match("(%a%a%a)")
  if days[fd] then seq[3] = seq[1] seq[1] = "" seq[2] = seq[2] or "" end
  if months[fd] then seq[2] = seq[1] seq[1] = "" end
  while #seq < 3 do seq[#seq+1] = "" end
  seq = Util.map(function(w) return split(w,",") end, seq)   -- split sequences "3,4"
  local lim = {{min=1,max=31},{min=1,max=12},{min=1,max=7}}
  seq = Util.map(function(t) local m = table.remove(lim,1);
      return flatten(Util.map(function (g) return expandCron({g,m}) end, t))
    end, seq) -- expand intervalls "3-5"
  local dateSeq = Util.map(seq2map,seq)
  return function()
    local t = os.date("*t",osTime())
    return
    (next(dateSeq[1]) == nil or dateSeq[1][t.day]) and    -- day     1-31
    (next(dateSeq[2]) == nil or dateSeq[2][t.month]) and  -- month   1-12
    (next(dateSeq[3]) == nil or dateSeq[3][t.wday])       -- weekday 1-7, 1=sun, 7=sat
  end
end

ScriptEngine.defineInstr("date",function(s,n,e,i)
    local ts = s.pop()
    if ts ~= i[5] then i[6] = Util.dateTest(ts); i[5] = ts end -- cache fun
    s.push(i[6]())
  end)
ScriptEngine.defineInstr("day",function(s,n,e,i)
    local ts = s.pop()
    if ts ~= i[5] then i[6] = Util.dateTest(ts); i[5] = ts end -- cache fun
    s.push(i[6]())
  end)
ScriptEngine.defineInstr("hour",function(s,n,e,i)
    local ts = s.pop()
    if ts ~= i[5] then i[6] = Util.dateTest(ts); i[5] = ts end -- cache fun
    s.push(i[6]())
  end)

function Util.mapAnd(f,l,s) s = s or 1; local e=false for i=s,#l do e = f(l[i]) if not e then return false end end return e end 
function Util.mapOr(f,l,s) s = s or 1; for i=s,#l do local e = f(l[i]) if e then return e end end return false end
function Util.mapF(f,l,s) s = s or 1; local e=true for i=s,#l do e = f(l[i]) end return e end
function Util.map(f,l,s) s = s or 1; local r={} for i=s,#l do r[#r+1] = f(l[i]) end return r end
function Util.mapo(f,l,o) for _,j in ipairs(l) do f(o,j) end end
function Util.member(v,tab) for _,e in ipairs(tab) do if v==e then return e end return nil end end

Util.S1 = {click = "16", double = "14", tripple = "15", hold = "12", release = "13"}
Util.S2 = {click = "26", double = "24", tripple = "25", hold = "22", release = "23"}

Util._vars = {} 

function Util.defvar(var,expr) Util.setVar(Util.v(var),expr) end

function Util.v(path)
  local res = {} 
  for token in path:gmatch("[%$%w_]+") do res[#res+1] = token end
  return {'var',res}
end

function Util.getVar(var)
  _assertf(type(var) == 'table' and var[1]=='var',"Bad variable: %s",function() return json.encode(var) end)
  local vars,path = Util._vars,var[2]
  for i=1,#path do 
    if vars == nil then return nil end
    if type(vars) ~= 'table' then return error("Undefined var:"..table.concat(path,".")) end
    vars = vars[path[i]]
  end
  return vars
end

function Util.setVar(var,expr)
  _assertf(type(var) == 'table' and var[1]=='var',"Bad variable: %s",function() return json.encode(var) end)
  local vars,path = Util._vars,var[2]
  for i=1,#path-1 do 
    if type(vars[path[i]]) ~= 'table' then vars[path[i]] = {} end
    vars = vars[path[i]]
  end
  vars[path[#path]] = expr
  return expr
end

Util._reverseVarTable = {}
function Util.reverseMapDef(table) Util._reverseMap({},table) end

function Util._reverseMap(path,value)
  if type(value) == 'number' then
    Util._reverseVarTable[tostring(value)] = table.concat(path,".")
  elseif type(value) == 'table' and not value[1] then
    for k,v in pairs(value) do
      table.insert(path,k) 
      Util._reverseMap(path,v)
      table.remove(path) 
    end
  end
end

function Util.reverseVar(id) return Util._reverseVarTable[tostring(id)] or id end

Util.gKeys = {type=1,deviceID=2,value=3,val=4,key=5,arg=6,event=7,events=8,msg=9,res=10}
Util.gKeysNext = 10
function Util._keyCompare(a,b)
  local av,bv = Util.gKeys[a], Util.gKeys[b]
  if av == nil then Util.gKeysNext = Util.gKeysNext+1 Util.gKeys[a] = Util.gKeysNext av = Util.gKeysNext end
  if bv == nil then Util.gKeysNext = Util.gKeysNext+1 Util.gKeys[b] = Util.gKeysNext bv = Util.gKeysNext end
  return av < bv
end

function Util.prettyJson(e) -- our own json encode, as we don't have 'pure' json structs
  local res,t = {}
  local function pretty(e)
    local t = type(e)
    if t == 'string' then res[#res+1] = '"' res[#res+1] = e res[#res+1] = '"' 
    elseif t == 'number' then res[#res+1] = e
    elseif t == 'boolean' or t == 'function' then res[#res+1] = tostring(e)
    elseif t == 'table' then
      if e[1] then
        res[#res+1] = "[" pretty(e[1])
        for i=2,#e do res[#res+1] = "," pretty(e[i]) end
        res[#res+1] = "]"
      else
        if e._var_  then res[#res+1] = _format('"%s"',e._str) return end
        local k = {} for key,_ in pairs(e) do k[#k+1] = key end 
        table.sort(k,Util._keyCompare)
        if #k == 0 then res[#res+1] = "[]" return end
        res[#res+1] = '{'; res[#res+1] = '"' res[#res+1] = k[1]; res[#res+1] = '":' t = k[1] pretty(e[t])
        for i=2,#k do 
          res[#res+1] = ',"' res[#res+1] = k[i]; res[#res+1] = '":' t = k[i] pretty(e[t]) 
        end
        res[#res+1] = '}'
      end
    elseif e == nil then return "nil"
    else error("bad json expr:"..tostring(e)) end
  end
  pretty(e)
  return table.concat(res)
end
Util.tojson = Util.prettyJson


Rule = newRuleCompiler()
---------------- Extra setup ----------------
-- Support for CentralSceneEvent & WeatherChangedEvent
  _lastCSEvent = {}
  _lastWeatherEvent = {}
  Event:event({type='event'}, function(env) env.event.event._sh = true post(env.event.event) end)
  Event:event({type='CentralSceneEvent'}, 
    function(env) _lastCSEvent[env.event.data.deviceId] = env.event.data end)
  Event:event({type='WeatherChangedEvent'}, 
    function(env) _lastWeatherEvent[env.event.data.change] = env.event.data; _lastWeatherEvent['*'] = env.event.data end)

  local function mkCS(id) return {type='CentralSceneEvent',data={deviceId=id}} end
  Rule.defineTrigger('csEvent',
    function(s,n,a,e) return s.push(_lastCSEvent[s.pop()]) end,
    function(s,n,a,e) e.id[s.pop()]=mkCS s.push(true) end)
    local function mkW(id) return {type='WeatherChangedEvent',data={changed=id}} end
  Rule.defineTrigger('weather',
    function(s,n,e) local k = n>0 and s.pop() or '*'; return s.push(_lastWeatherEvent[k]) end,
    function(s,n,e) if n>0 then e.id[s.pop()]=mkW else e.id['*']=function() return {type='WeatherChangedEvent'} end end s.push(true) end)

--- SceneActivation constants
  Util.defvar('S1',Util.S1)
  Util.defvar('S2',Util.S2)

---- Print rule definition -------------

function printRule(e)
  print(_format("Event:%s",Util.prettyJson(e[Event.RULE])))
  local code = _compiledCode[e.action]
  local scr = _compiledScript[code]
  local expr = _compiledExpr[scr]

  if expr then Log(LOG.LOG,"Expr:%s",expr) end
  if scr then Log(LOG.LOG,"Script:%s",Util.prettyJson(scr)) end
  if code then Log(LOG.LOG,"Code:") ScriptCompiler.dump(code) end
  Log(LOG.LOG,"Addr:%s",tostring(e.action))
end

---------------------- Startup -----------------------------    
if _type == 'autostart' or _type == 'other' then
  Log(LOG.WELCOME,_format("%sEventRunner v%s",_sceneName and (_sceneName.." - " or ""),_version))

  if _HC2 and fibaro:getGlobalModificationTime(_MAILBOX) == nil then
    api.post("/globalVariables/",{name=_MAILBOX})
  end

  if _HC2 then _poll() end -- start polling mailbox

  Log(LOG.SYSTEM,"Loading rules")
  local status, res = pcall(function() main() end)
  if not status then Log(LOG.ERROR,"Error loading rules:%s",type(res)=='table' and table.concat(res,' ') or res) fibaro:abort() end

  _trigger.type = 'start' -- 'startup' and 'other' -> 'start'
  _trigger._sh = true
  Event:post(_trigger)

  Log(LOG.SYSTEM,"Scene running")
  Log(LOG.SYSTEM,"Sunrise %s, Sunset %s",fibaro:getValue(1,'sunriseHour'),fibaro:getValue(1,'sunsetHour'))
  if _OFFLINE then _System.runTimers() end
end