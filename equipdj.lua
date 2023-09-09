-- 装备叠加
local logger = LuaLogModule(LuaLogLevel.ERROR)
local EquipPlayerDieJiaCnt = "EquipPlayerDieJiaCnt" -- 玩家进行叠加的总次数(包含失败)

-- 持久化追加总次数数据
local function AddPlayerDieJiaCnt(p)
    local cnt = EquipGetPlayerDieJiaCnt(p) + 1
    p.vars:setuint(EquipPlayerDieJiaCnt, cnt, true, 0)
end
function EquipGetPlayerDieJiaCnt(p)
    return p.vars:getuint(EquipPlayerDieJiaCnt)
end

-- 幸运石场景下计算成功率
local function AddSuccessCof(p, count, totalsuccof, stage, luckystoneindex, luckycost)
    local errcode = EQUIP_ERROR.SUCCESS
    repeat
        if count ~= nil then
            count = tonumber(count)
            if count == 0 then
                break
            end
            local usestonestage = stage - EquipDieJiaConfig.nouseluckystonestage -- 计算满足使用幸运石的条件
            if usestonestage <= 0 then
                errcode = EQUIP_ERROR.NOOPEN
                break
            end
            local luckystonestageconfig = nil -- 获取幸运石配置
            if luckystoneindex == nil or EquipDieJiaConfig.luckystone[luckystoneindex] == nil or EquipDieJiaConfig.luckystone[luckystoneindex][stage] == nil then
                logger.info("luckystoneindex ", luckystoneindex, " stage ", stage)
                errcode = EQUIP_ERROR.UNKNOW
                break
            end
            local luckystonestageconfig = EquipDieJiaConfig.luckystone[luckystoneindex][stage] 
            local configitemid = luckystonestageconfig.itemid
            local tmptable = {
                itemid = configitemid,
                itemcnt = count
            }
            if IsItemEnough(p, {tmptable}) ~= 0 then
                errcode = EQUIP_ERROR.NOCOST
                break
            end
            logger.info(p.name, "使用幸运石", count, "每颗增加成功率", luckystonestageconfig.addcof)
            totalsuccof = totalsuccof + (count * luckystonestageconfig.addcof) -- 计算使用石头增加的成功率
            if totalsuccof > EquipDieJiaConfig.useluckystonemaxcof then 
                totalsuccof = EquipDieJiaConfig.useluckystonemaxcof
            end
            table.insert(luckycost, tmptable)
        end
    until true
    return errcode, totalsuccof
end

--[[
    note: 装备叠加
    param:
        mainonlyid 主装备id
        subonlyid 副装备id
        count 叠加幸运石数量
        lockinfo 锁定的卓越属性信息
]]
--@dolua call=__a__Equip_DieJia(8034011205140752,8034015500108048)
function __a__Equip_DieJia(p, mainonlyid, subonlyid, count, lockinfo)
    if p == nil or mainonlyid == nil or subonlyid == nil then
        return
    end
    local errcode = EQUIP_ERROR.SUCCESS
    local sendmsg = {}
    sendmsg.issuccess = 0
    local log ="[装备叠加]: " .. " monlyid: " .. mainonlyid .. " sonlyid: " .. subonlyid
   	local gconsumeindex = 0 --叠加类型 emEquipDJType
    repeat
        if mainonlyid == subonlyid then
            errcode = EQUIP_ERROR.SAMEITEM
            break
        end
        local mainitem,packagetype = EquipGetItemAndPackageType(p, mainonlyid) -- 主装备
        local subitem, subpackagetype = EquipGetItemAndPackageType(p, subonlyid) -- 副装备
        if mainitem == nil or subitem == nil then
            errcode = EQUIP_ERROR.NOITEM
            break
        end
        if mainitem.itembase.itemid ~= subitem.itembase.itemid then
            errcode = EQUIP_ERROR.ITEMNOTSAME
            break
        end
        local mainsubtype = mainitem.itembase.subtype
        local maintype = mainitem.itembase.type
        local isnormalequip = true 
        local djtype = emOtherPropFrom.OTHERPROPFROM_EXCELLENCE
        local groupconfig = nil
        local maxcexcellencecnt = EquipDieJiaConfig.maxcexcellencecnt
        if maintype == emItemType.ITEM_TYPE_EQUIP then
            if mainsubtype == emItemSubType.ITEM_SUBEQUIP_WING then 
                djtype = emOtherPropFrom.OTHERPROPFROM_WINGENTRYATTRI
                isnormalequip = false
            end
            groupconfig = EquipDieJiaPartGroupConfig[mainsubtype]
        elseif maintype == emItemType.ITEM_TYPE_GUARD then
            isnormalequip = false 
            djtype = emOtherPropFrom.OTHERPROPFROM_GUARDATTRI
            groupconfig = EquipGuardDieJiaPartGroupConfig[mainsubtype]
            maxcexcellencecnt = EquipGuardDieJiaConfig.maxcexcellencecnt
             --添加守护追加强化的互换逻辑！！！
            local oldqhlv = mainitem.iteminfo:getextdata(EXTDATA_INDEX.Guard_StrengthLv) 
            local oldzjlv = mainitem.iteminfo:getextdata(EXTDATA_INDEX.Guard_ZhuiJiaLv)
            local newqhlv = subitem.iteminfo:getextdata(EXTDATA_INDEX.Guard_StrengthLv)
            local newzjlv = subitem.iteminfo:getextdata(EXTDATA_INDEX.Guard_ZhuiJiaLv)
            if oldqhlv < newqhlv then
                mainitem.iteminfo:setextdata(EXTDATA_INDEX.Guard_StrengthLv, newqhlv)
            end
            if oldzjlv < newzjlv then
                mainitem.iteminfo:setextdata(EXTDATA_INDEX.Guard_ZhuiJiaLv, newzjlv)
            end
        end
        if groupconfig == nil then
            logger.info("mainsubtype ", mainsubtype)
            errcode = EQUIP_ERROR.UNKNOW
            break
        end
        if isnormalequip and (mainitem.itembase.quality ~= EquipDieJiaConfig.minquality) then -- 套装品质的装备才可以进行叠加操作
            errcode = EQUIP_ERROR.WRONGEQUIP
            break
        end
        if subpackagetype == emPackageType.PACKAGE_EQUIP then -- 已装备不能作为副装备
            errcode = EQUIP_ERROR.WRONGPOS
            break
        end
        local subitemnp = {}
        subitem:loadnp(subitemnp)
        local mainitemnp = {}
        mainitem:loadnp(mainitemnp)
        local mainitemattr = {}
        local mainitemattrcnt = 0
        for _, v in pairs(mainitemnp) do -- 获取主装备的卓越词条
            if v.from == djtype then
                mainitemattr[v.type] = v.value
                mainitemattrcnt = mainitemattrcnt + 1
            end
        end
        local diffattr = {}
        local subitemattr = {}
        local subitemattrcnt = 0
        if maintype == emItemType.ITEM_TYPE_GUARD then
            local guard_id=mainitem.itembase.itemid
            local subitemattr = GuardAttributeLib[guard_id].EffectConf 
            for k, v in pairs(subitemattr) do -- 获取主装备里没有的守护词条，
                if mainitemattr[k] == nil then
                    table.insert(diffattr, {
                        type = k,
                        value = v
                    })
                end
            end
        else            
            for _, v in pairs(subitemnp) do -- 获取副装备的卓越词条
                if v.from == djtype then
                    subitemattr[v.type] = v.value
                    subitemattrcnt = subitemattrcnt + 1
                end
            end
        end
        for k, v in pairs(subitemattr) do -- 获取主装备里没有的副装备里的卓越词条
            if mainitemattr[k] == nil then
                table.insert(diffattr, {
                    type = k,
                    value = v
                })
            end
        end
        logger.info(p.name, "差异的卓越词条", diffattr)
        if #diffattr <= 0 then  
            errcode = EQUIP_ERROR.NOEXCELLENCE
            break
        end
        local stage = mainitem.itembase.stage -- 物品的阶位 
        gconsumeindex = groupconfig.consume -- 获取消耗配置索引
        local costconfig = EquipDieJiaConfig.consume[gconsumeindex] -- 获取消耗配置
        if costconfig == nil then
            logger.info("gconsumeindex ", gconsumeindex)
            errcode = EQUIP_ERROR.UNKNOW
            break
        end 
        local cost = nil
        if isnormalequip == false then 
            cost = costconfig[stage] -- 翅膀守护叠加消耗跟阶位相关
        else
            cost = costconfig[1] -- 武器防具装备消耗固定
        end
        if cost == nil then
            logger.info("isnormalequip ", isnormalequip, " stage ", stage)
            errcode = EQUIP_ERROR.UNKNOW
            break
        end
        if IsItemEnough(p, {cost}) ~= 0 then --  消耗材料 
            errcode = EQUIP_ERROR.NOCOST
            break
        end
        -- 锁定信息
        local lockattrtype = {}
        local lockcost = {}
        if lockinfo ~= nil then
            lockattrtype = split(lockinfo, "+")
            local lockcnt = #lockattrtype
            local maxlockcnt = EquipDieJiaConfig.maxlockcnt
            local lockstoneid = EquipDieJiaConfig.lockstoneid
            if maintype == emItemType.ITEM_TYPE_GUARD then
                maxlockcnt = EquipGuardDieJiaConfig.maxlockcnt
                lockstoneid = EquipGuardDieJiaConfig.lockstoneid
            end
            if lockcnt > 0 then
                if lockcnt > maxlockcnt then
                    errcode = EQUIP_ERROR.MAXLOCKCNT
                    break
                end
                local _lockstoneCnt = EquipDieJiaConfig.lockstone[lockcnt]
                if _lockstoneCnt == nil then
                    errcode = EQUIP_ERROR.UNKNOW
                    break
                end
                table.insert(lockcost, {
                    itemid = lockstoneid,
                    itemcnt = _lockstoneCnt
                })
            end
        end
        if next(lockcost) ~= nil and IsItemEnough(p, lockcost) ~= 0 then -- 锁定石头不够
            errcode = EQUIP_ERROR.NOCOST
            break
        end
        local totalsuccof = 0
        local luckycost = {}
        if isnormalequip then -- 武器防具成功率计算
            totalsuccof = EquipDieJiaConfig.succof[stage]
            if totalsuccof == nil then
                errcode = EQUIP_ERROR.UNKNOW
                break
            end
            errcode, totalsuccof = AddSuccessCof(p, count, totalsuccof, stage, groupconfig.luckystone, luckycost) 
        else 
            totalsuccof = 10000 -- 翅膀防具100%成功率
        end
        if errcode ~= EQUIP_ERROR.SUCCESS then
            break
        end
        DeductBagItem(p, {cost}, "叠加消耗") -- 叠加消耗材料
        DeductBagItem(p, lockcost, "叠加消耗") -- 消耗锁定原石
        DeductBagItem(p, luckycost, "叠加消耗") -- 消耗幸运石原石
        local rate = math.random(1, 10000)  -- 概率随机
        log = log .. "mid:" .. mainitem.itembase.itemid .. " sid: " .. subitem.itembase.itemid .. " djtype: " .. djtype .. " maxexcnt: " .. maxcexcellencecnt .. " diffattr: " ..  table.serialize(diffattr)  .. " lockattr: "  .. " tsuccrate: " .. totalsuccof .. " csuccrate: " .. rate
        AddPlayerDieJiaCnt(p)
        if totalsuccof < rate then -- 叠加失败
                p.packagemanage:delitembyobj(subpackagetype, subitem, 1, "装备叠加")
                if mainitemattrcnt < maxcexcellencecnt then
                -- 随机增加属性的逻辑
                    local rnd = math.random(1, #diffattr)
                    local type = diffattr[rnd].type
                    local value = diffattr[rnd].value
                    mainitemattr[type] = value
                else
                    local tmpattr = {}
                    local tmpmainattr = {}
                    -- 进入需要替换掉原有的属性的逻辑
                    for k, v in pairs(mainitemattr) do
                        local isinsert = true
                        for _, n in pairs(lockattrtype) do
                            if tonumber(k) == tonumber(n) then
                                isinsert = false
                                break
                            end
                        end
                        if isinsert then
                            table.insert(tmpattr, k)
                        end
                    end
                    local rnd = math.random(1, #tmpattr)
                    local deltype = tmpattr[rnd]
                    for k, v in pairs(mainitemattr) do
                        if k ~= deltype then
                            tmpmainattr[k] = v
                        end
                    end
        
                    rnd = math.random(1, #diffattr)
                    local type = diffattr[rnd].type
                    local value = diffattr[rnd].value
                    tmpmainattr[type] = value
                    mainitemattr = tmpmainattr
                    logger.info(p.name, "叠加成功，属性=", type, " 值=", value)
                    logger.info(p.name, "删除，属性=", deltype)
                end 
                break
        end

        local resetnp = {}
        for k, v in pairs(mainitemattr) do
            table.insert(resetnp, {
                from = djtype,
                type = k,
                value = v
            })
        end 
        for __, v in pairs(mainitemnp) do
            if v.from ~= djtype then
                table.insert(resetnp, {
                    from = v.from,
                    type = v.type,
                    value = v.value
                })
            end
        end  
        logger.info(p.name, "重置卓越属性", resetnp)
        --logger.error(table.serialize(resetnp))
        mainitem:resetnp(resetnp, #resetnp) -- 叠加后属性重置
        log = log .. " nattr: " .. table.serialize(resetnp)
        p.packagemanage:delitembyobj(subpackagetype, subitem, 1, "装备叠加消耗")
        -- 属性刷新
        mainitem.iteminfo:setextdata(EXTDATA_INDEX.DIEJIA_NO_TRANSACTION, 1)
        p.packagemanage:senditeminfo(mainitem, false)
        p.packagemanage:refreshequipability()
        p.packagemanage:refreshguardability()
        p:refreshability(true)
        p:refreshfreature(true)
        sendmsg.issuccess = 1
        logger.info("[", p.name, "]叠加主装备 ", mainitem.iteminfo.itemid, " 成功", " 消耗材料 ",
            table.serialize(cost), "消耗锁定石 ", table.serialize(lockcost), "消耗幸运石 ",
            table.serialize(luckycost))
        if packagetype == emPackageType.PACKAGE_GUARD then
            p:setnotifysuperupdateplayer(emUpdateSuperPlayerType.UpdateSuperPlayerType_GUARD)
        end      
    until true
    Vip_UpdateWearQuestProgress(p)
    Quest_SendQuestEvent(p, emQuestEvent.USEMERGE, 1, EquipGetPlayerDieJiaCnt(p))
    logger.info(p.name, "叠加返回码 ", errcode, sendmsg)
    p:sendscriptdata(FuncType_Equip_Main, FuncType_Equip_DieJia, errcode, cjson.encodeobj(sendmsg))
    log = log .. " success " .. sendmsg.issuccess
    if errcode == EQUIP_ERROR.SUCCESS then
        -- 发送叠加日志
        lgamelog:sendplayabilitylog(p, emLogPlayType.EquipDJ, emLogPlayProcess.Succeed, log)
        ActiveTaskEvent_OnDieJia(p,gconsumeindex,sendmsg.issuccess)
    end
end

-- 获取elitecnt条卓越属性的装备数量
function EquipGetNumByDeiJieEliteAttrCnt(p, elitecnt)
    local cnt = 0
    if p == nil or elitecnt == nil then
        return cnt
    end       
    for i = emEquipPosition.EQUIP_POS_WEAPON_RIGHT, emEquipPosition.EQUIP_POS_TALISMAN do
        local _cnt = EquipGetEliteAttrsByPackageTypeAndPos(p, emPackageType.PACKAGE_EQUIP, i)
        if _cnt >= elitecnt then
            cnt = cnt + 1
        end
    end
    return cnt
end

-- 根据背包类型及位置获取装备的卓越属性数量
function EquipGetEliteAttrsByPackageTypeAndPos(p, packagetype, pos)
    local cnt = 0
    repeat
        if p == nil or packagetype == nil or pos == nil then
            break
        end 
        local item = p.packagemanage:findpackageitembypos(packagetype, pos)
        if item then
            local itemnp = {}
            item:loadnp(itemnp)
            for _, v in pairs(itemnp) do 
                if v.from == emOtherPropFrom.OTHERPROPFROM_EXCELLENCE then
                    cnt = cnt + 1
                end
            end
        end
    until true
    logger.info(p.name, "背包", packagetype, "位置", pos, "卓越属性数量", cnt)
    return cnt 
end