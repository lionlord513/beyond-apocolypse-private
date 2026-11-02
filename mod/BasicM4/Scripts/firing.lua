-- Follow-up shots execute only on the locally controlled shooter's native gun.
return function(valid)
    local F={}
    function F.reset() F.actor=nil;F.ammo=nil;F.left=0;F.next=0;F.armed=0;F.down=false end
    F.reset()
    function F.tick(a,def,now,alive,pressed)
        if not valid(a) or not alive or not def or def.Mode~='burst' then F.reset();return end
        if not valid(F.actor) or F.actor:GetAddress()~=a:GetAddress() then
            F.reset();F.actor=a;F.ammo=a.NbBullet;return
        end
        local ammo=a.NbBullet
        if pressed~=nil then
            -- A remote ammunition acknowledgement must never start a new burst.
            -- Only the local trigger edge arms the two native follow-up shots.
            if pressed and not F.down then F.armed=now+.75 end
            F.down=pressed
            if ammo>F.ammo or (a.IsAttacking or 0)>def.FireRate+.05 then F.left=0;F.armed=0 end
            if ammo<F.ammo and now<=F.armed then F.left=math.max(0,3-(F.ammo-ammo));F.next=now+def.FireRate+.005;F.armed=0 end
            F.ammo=ammo
            if ammo<=0 then F.left=0 end
            if F.left>0 and now>=F.next then
                F.left=F.left-1;F.next=now+def.FireRate+.005
                a:TriggerAttack(false);F.ammo=a.NbBullet
            end
            return
        end
        -- Native reload/equip lock is longer than the ordinary shot lock.
        if (a.IsAttacking or 0)>def.FireRate+0.05 then F.left=0;F.ammo=ammo;return end
        if ammo>F.ammo then F.left=0 end
        if ammo<F.ammo then
            local spent=F.ammo-ammo
            F.left=F.left>0 and math.max(0,F.left-spent) or math.max(0,3-spent)
            F.next=now+def.FireRate+0.005
        end
        F.ammo=ammo
        if ammo<=0 then F.left=0 end
        if F.left>0 and now>=F.next then
            local before=a.NbBullet
            a:TriggerAttack(false)
            F.ammo=a.NbBullet
            if F.ammo<before then F.left=math.max(0,F.left-(before-F.ammo)) else F.left=0 end
            F.next=now+def.FireRate+0.005
        end
    end
    return F
end
