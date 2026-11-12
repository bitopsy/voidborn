import os, json, math
G = '/home/claude/vb/game'
meta = json.load(open('/home/claude/vb/out/meta.json'))

# ---------------------------------------------------------------- lua serializer
def lua(v, ind=0):
    pad = '\t' * ind
    if isinstance(v, bool): return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return repr(round(v, 4)) if isinstance(v, float) else str(v)
    if isinstance(v, str): return '"' + v.replace('\\', '\\\\').replace('"', '\\"') + '"'
    if isinstance(v, (list, tuple)):
        if all(not isinstance(x, (dict, list)) for x in v):
            return '{ ' + ', '.join(lua(x) for x in v) + ' }'
        return '{\n' + ''.join(pad + '\t' + lua(x, ind + 1) + ',\n' for x in v) + pad + '}'
    if isinstance(v, dict):
        return '{\n' + ''.join(f'{pad}\t{k} = {lua(x, ind + 1)},\n' for k, x in v.items()) + pad + '}'
    raise TypeError(v)

# ---------------------------------------------------------------- weapon builders
CEG = {'choir': 'vb_choir_hit', 'maw': 'vb_maw_hit'}
def laser(fac, rng, reload, dmg, rgb, thick=2.0, aoe=8, vel=900, core=0.6, flare=4, burst=1, burstrate=0.1, name='Gaze'):
    return dict(name=name, weaponType='LaserCannon', range=rng, reloadTime=reload, damage={'default': dmg}, areaOfEffect=aoe,
                weaponVelocity=vel, rgbColor=rgb, thickness=thick, coreThickness=core, laserFlareSize=flare, duration=0.12,
                explosionGenerator='custom:' + CEG[fac], tolerance=8000, turret=True, avoidFriendly=False, collideFriendly=False,
                collideFeature=False, intensity=0.9, texture1='largebeam', texture2='laserend', texture3='flare',
                texture4='flare', burst=burst, burstRate=burstrate, sprayAngle=200, edgeEffectiveness=0.3, impulseFactor=0.2,
                size=thick)
def missile(fac, rng, reload, dmg, burst=1, aoe=40, vel=320, color='0.7 1 0.2', name='Spores'):
    return dict(name=name, weaponType='MissileLauncher', range=rng, reloadTime=reload, damage={'default': dmg}, areaOfEffect=aoe,
                weaponVelocity=vel, startVelocity=140, weaponAcceleration=160, flightTime=5, tracks=True, turnRate=9000, smokeTrail=True,
                explosionGenerator='custom:' + CEG[fac], turret=True, avoidFriendly=False, collideFriendly=False,
                burst=burst, burstRate=0.18, size=3.0, rgbColor=color, texture1='flare', texture2='smoketrail', cegTag='',
                edgeEffectiveness=0.3, impulseFactor=0.2, tolerance=12000, dance=20, wobble=2500, trajectoryHeight=0.4)
def flame(rng, reload, dmg, name='Maw Breath'):
    return dict(name=name, weaponType='Flame', range=rng, reloadTime=reload, damage={'default': dmg}, areaOfEffect=14,
                weaponVelocity=260, sizeGrowth=1.4, size=6, flameGfxTime=1.0, colorMap='0.4 1 0.2 0.5  0.9 0.9 0.1 0.3  0.9 0.2 0.0 0.2  0 0 0 0.0',
                explosionGenerator='', turret=True, avoidFriendly=False, collideFriendly=False, fireStarter=0,
                tolerance=4000, texture1='flame', impulseFactor=0.0, edgeEffectiveness=0.5)
def dgun(fac, name, rgb):
    return dict(name=name, weaponType='DGun', range=240, reloadTime=1.4, damage={'default': 2600}, areaOfEffect=64, weaponVelocity=320,
                commandFire=True, noExplode=True, collideFriendly=False, collideFeature=False, avoidFriendly=False, turret=True,
                explosionGenerator='custom:vb_boom_med', rgbColor=rgb, size=22, energyPerShot=500, tolerance=4000,
                texture1='circularthingy', texture2='flare', sprayAngle=0, impulseFactor=0.0, edgeEffectiveness=0.5, fireStarter=100,
                range_dgun=1)

# ---------------------------------------------------------------- unit table
# kind: com con scout/raider/assault/art/support/heavy ; fac/mex/solar/heart/store/radar/def1/def2
def U(id, fac, name, desc, kind, m, hp, **kw):
    d = dict(id=id, fac=fac, name=name, desc=desc, kind=kind, m=m, hp=hp); d.update(kw); return d

CB = lambda p: [p + x for x in ('siphon', 'sunpetal', 'heart', 'vault', 'watcher', 'stare', 'pillar')]
UNITS = [
 # ---------------- CHOIR OF THE EYE
 U('ch_hierophant', 'choir', 'Hierophant', 'Cyclopean Commander - builds, sees all, burns what it stares at', 'com', 2500, 4200, speed=1.9, alt=45, sight=620,
   build=['ch_womb'] + CB('ch_')[:0] + ['ch_siphon', 'ch_sunpetal', 'ch_heart', 'ch_vault', 'ch_watcher', 'ch_stare', 'ch_pillar'], bp=95, bd=190,
   weapons=[laser('choir', 430, 0.55, 43, '0.55 0.95 1.0', 3.0, 10, name='Gaze'), dgun('choir', 'Cataract Stare', '0.5 0.8 1.0')], hover=True),
 U('ch_seer', 'choir', 'Seer', 'Builder - a floating eye with tendrils that knit flesh into structures', 'con', 90, 520, speed=2.8, alt=50, sight=480,
   build=['ch_womb', 'ch_siphon', 'ch_sunpetal', 'ch_heart', 'ch_vault', 'ch_watcher', 'ch_stare', 'ch_pillar'], bp=70, bd=185),
 U('ch_gazer', 'choir', 'Gazer', 'Scout - fast flying eyeling with a pinprick laser', 'scout', 38, 230, speed=5.0, alt=95, sight=720,
   weapons=[laser('choir', 270, 0.5, 6, '0.5 1 1', 1.6, 6, name='Pinprick')]),
 U('ch_lashling', 'choir', 'Lashling', 'Raider - cheap tentacle dart that swarms in packs', 'raider', 55, 330, speed=3.7, alt=65, sight=450,
   weapons=[laser('choir', 215, 0.3, 6.6, '0.9 0.5 1', 1.8, 6, name='Lash Pulse')]),
 U('ch_hoplite', 'choir', 'Cyclops Hoplite', 'Assault - one-eyed brute with club-arms and a heavy gaze', 'assault', 195, 1400, speed=2.0, alt=95, sight=520,
   weapons=[laser('choir', 380, 0.6, 34, '0.4 0.9 1', 3.2, 12, name='Cyclops Gaze')]),
 U('ch_basilisk', 'choir', 'Basilisk', 'Long range - serpent whose gaze reaches across the void', 'art', 250, 560, speed=1.9, alt=150, sight=800,
   weapons=[laser('choir', 740, 2.0, 95, '1 0.9 0.4', 2.6, 10, vel=1500, name='Petrifying Beam')]),
 U('ch_weeper', 'choir', 'Weeper', 'Support - a drifting jelly-eye that mends allies with its tears', 'support', 150, 700, speed=2.4, alt=105, sight=500, bp=38, bd=150),
 U('ch_colossus', 'choir', 'Argus Colossus', 'Heavy - hundred-eyed titan; its great eye unmakes whole squads', 'heavy', 1650, 9500, speed=1.05, alt=230, sight=700,
   weapons=[laser('choir', 650, 1.2, 330, '1 0.6 1', 8.0, 52, vel=1200, core=0.8, flare=12, name='Annihilating Gaze'),
            laser('choir', 380, 0.5, 30, '0.5 1 1', 2.2, 10, name='Lesser Eyes')]),
 U('ch_womb', 'choir', 'Iris Womb', 'Factory - the Choir births its army through an unblinking pool', 'fac', 470, 3300, fp=6, build=['ch_seer', 'ch_gazer', 'ch_lashling', 'ch_hoplite', 'ch_basilisk', 'ch_weeper', 'ch_colossus'], bp=100, e=1300, bt=4600, sight=420),
 U('ch_siphon', 'choir', 'Leech Eye', 'Metal extractor - drinks ore from asteroid marrow', 'mex', 42, 480, fp=2, e=360, bt=1300, sight=240),
 U('ch_sunpetal', 'choir', 'Sun Iris', 'Energy - an iris that drinks starlight', 'solar', 85, 620, fp=3, e=0, bt=1500, sight=260, energy=22),
 U('ch_heart', 'choir', 'Singularity Heart', 'Advanced energy - a caged pinprick black hole', 'heart', 1100, 3600, fp=5, e=4200, bt=18000, sight=300, energy=500),
 U('ch_vault', 'choir', 'Tear Vault', 'Storage - a glistening reservoir of metal and energy', 'store', 190, 2400, fp=4, e=300, bt=3000, sight=260, ms=1500, es=4000),
 U('ch_watcher', 'choir', 'Watcher', 'Radar - a tall stalk with a far-seeing eye', 'radar', 60, 420, fp=2, e=520, bt=1800, sight=480, radar=2300),
 U('ch_stare', 'choir', 'Stare Stalk', 'Light defence - an eye on a stalk that never blinks', 'def1', 95, 1000, fp=2, e=420, bt=2400, sight=560,
   weapons=[laser('choir', 540, 0.4, 16, '0.6 1 1', 2.0, 8, name='Stare')]),
 U('ch_pillar', 'choir', 'Pillar of Judgement', 'Heavy defence - a tower crowned with a colossal eye', 'def2', 540, 5200, fp=4, e=3300, bt=9500, sight=800,
   weapons=[laser('choir', 900, 1.6, 260, '1 0.7 1', 5.0, 40, vel=1400, core=0.8, flare=9, name='Judgement')]),
 # ---------------- MAW SWARM
 U('mw_matriarch', 'maw', 'Matriarch', 'Maw Commander - a gnashing hive-mother that digests its foes', 'com', 2500, 4400, speed=1.8, alt=45, sight=560,
   build=['mw_hive', 'mw_extractor', 'mw_sunbloom', 'mw_core', 'mw_cyst', 'mw_sensor', 'mw_spine', 'mw_bastion'], bp=95, bd=190,
   weapons=[laser('maw', 420, 0.55, 48, '0.7 1 0.2', 3.4, 10, name='Acid Spit'), dgun('maw', 'Devour', '0.6 1 0.1')], hover=True, heal=3),
 U('mw_weaver', 'maw', 'Weaver', 'Builder - a spidery spinner that secretes structures from silk', 'con', 90, 560, speed=2.6, alt=50, sight=450,
   build=['mw_hive', 'mw_extractor', 'mw_sunbloom', 'mw_core', 'mw_cyst', 'mw_sensor', 'mw_spine', 'mw_bastion'], bp=70, bd=185, heal=1),
 U('mw_skitter', 'maw', 'Skitter', 'Scout - flitting clawed bug with a single big eye', 'scout', 32, 240, speed=5.2, alt=90, sight=700,
   weapons=[laser('maw', 235, 0.5, 7, '0.6 1 0.2', 1.8, 6, name='Acid Dart')], heal=1),
 U('mw_gnasher', 'maw', 'Gnasher', 'Raider - flying jaws that scorch everything nearby', 'raider', 52, 560, speed=3.5, alt=60, sight=420,
   weapons=[flame(130, 0.1, 4.6)], heal=2),
 U('mw_ravager', 'maw', 'Ravager', 'Assault - armoured mandible beast spitting corrosive bolts', 'assault', 160, 2100, speed=1.9, alt=80, sight=480,
   weapons=[laser('maw', 345, 0.7, 46, '1 0.55 0.1', 3.6, 14, name='Corrosive Bolt')], heal=3),
 U('mw_spitter', 'maw', 'Spitter', 'Artillery - bloated sac that lobs homing spore-missiles', 'art', 205, 600, speed=1.7, alt=140, sight=700,
   weapons=[missile('maw', 820, 2.4, 118, aoe=48)], heal=1),
 U('mw_nurse', 'maw', 'Nurse', 'Support - floating brood-tender that stitches wounds', 'support', 150, 760, speed=2.2, alt=100, sight=480, bp=38, bd=150, heal=3),
 U('mw_leviathan', 'maw', 'Leviathan', 'Heavy - a mile of teeth swimming through vacuum', 'heavy', 1450, 13000, speed=1.0, alt=210, sight=640,
   weapons=[laser('maw', 620, 1.3, 380, '0.7 1 0.1', 9.0, 60, vel=1100, core=0.9, flare=12, name='Acid Cannon'),
            missile('maw', 520, 1.4, 30, burst=3, aoe=30, name='Spore Barrage')], heal=6),
 U('mw_hive', 'maw', 'Brood Hive', 'Factory - a pulsing mound that vomits out the swarm', 'fac', 420, 3500, fp=6, build=['mw_weaver', 'mw_skitter', 'mw_gnasher', 'mw_ravager', 'mw_spitter', 'mw_nurse', 'mw_leviathan'], bp=100, e=1250, bt=4500, sight=420, heal=4),
 U('mw_extractor', 'maw', 'Root Drill', 'Metal extractor - roots that bore into asteroid ore', 'mex', 40, 520, fp=2, e=340, bt=1300, sight=240, heal=1),
 U('mw_sunbloom', 'maw', 'Sunbloom', 'Energy - tentacle anemone feeding on starlight', 'solar', 82, 680, fp=3, e=0, bt=1500, sight=260, energy=22, heal=1),
 U('mw_core', 'maw', 'Heartfire Egg', 'Advanced energy - a caged egg that burns like a star', 'heart', 1050, 3900, fp=5, e=4000, bt=17500, sight=300, energy=500, heal=2),
 U('mw_cyst', 'maw', 'Gut Cyst', 'Storage - swollen sacs for metal and energy', 'store', 180, 2600, fp=4, e=280, bt=3000, sight=260, ms=1500, es=4000, heal=2),
 U('mw_sensor', 'maw', 'Listening Maw', 'Radar - a tall maw that hears the void', 'radar', 58, 450, fp=2, e=500, bt=1800, sight=460, radar=2300, heal=1),
 U('mw_spine', 'maw', 'Tooth Spire', 'Light defence - a fanged stalk that spits acid', 'def1', 90, 1100, fp=2, e=380, bt=2400, sight=540,
   weapons=[laser('maw', 500, 0.45, 19, '0.7 1 0.2', 2.4, 8, name='Acid Spit')], heal=2),
 U('mw_bastion', 'maw', 'Maw Bastion', 'Heavy defence - a titanic maw crowned with spore tubes', 'def2', 520, 5600, fp=4, e=3100, bt=9000, sight=780,
   weapons=[missile('maw', 860, 2.2, 85, burst=3, aoe=50, name='Spore Volley')], heal=4),
]
ID = {u['id']: u for u in UNITS}

# ---------------------------------------------------------------- build unitdefs
def unitdef(u):
    m = meta[u['id']]; k = u['kind']; fac = u['fac']
    d = dict(name=u['name'], description=u['desc'], objectName=u['id'] + '.s3o', buildPic=u['id'] + '.png',
             maxDamage=u['hp'], metalCost=u['m'], energyCost=u.get('e', u['m'] * 4), buildTime=u.get('bt', u['m'] * 9),
             sightDistance=u.get('sight', 450), category='VOIDBORN', iconType='default', capturable=False, autoHeal=u.get('heal', 0),
             idleAutoHeal=u.get('heal', 0) * 2, idleTime=300, explodeAs='vb_big' if k in ('heart', 'heavy', 'com') else 'vb_med' if u['m'] > 200 else 'vb_small',
             selfDestructAs='vb_big' if k in ('heart', 'heavy', 'com') else 'vb_med' if u['m'] > 200 else 'vb_small',
             customParams={'faction': fac, 'kind': k, 'iscommander': 'true' if k == 'com' else 'false'}, corpse='', mass=u['hp'] / 10 + u['m'])
    mobile = k in ('com', 'con', 'scout', 'raider', 'assault', 'art', 'support', 'heavy')
    if mobile:
        d.update(canMove=True, canFly=True, hoverAttack=True, cruiseAlt=u['alt'], maxVelocity=u['speed'], acceleration=0.06 + 0.08 / (1 + u['m'] / 200),
                 brakeRate=0.25, turnRate=700 if u['m'] < 500 else 400, dontLand=True, airStrafe=False, canSubmerge=False, maxWaterDepth=1000,
                 collide=True, crashDrag=0.02, useSmoothMesh=False, blocking=False, footprintX=2, footprintZ=2, upright=False, canAttack=bool(u.get('weapons')),
                 canPatrol=True, canGuard=True, canRepeat=True, moveState=1, fireState=2 if u.get('weapons') else 0,
                 radarDistance=0 if k != 'com' else 0, losEmitHeight=max(20, u['alt']), airSightDistance=u.get('sight', 450))
        d['mass'] = u['m'] + 100
    else:
        d.update(canMove=False, canAttack=bool(u.get('weapons')), blocking=True, upright=True, levelGround=False, footprintX=u['fp'], footprintZ=u['fp'],
                 repairable=True, reclaimable=True, floater=False, movementClass='', stealth=False,
                 crushResistance=100000, mass=100000)
        d.pop('movementClass')
    if k in ('com', 'con', 'support'):
        d.update(builder=True, workerTime=u['bp'], buildDistance=u['bd'], canReclaim=True, canAssist=True, canRepair=True, repairSpeed=u['bp'],
                 reclaimSpeed=u['bp'] * 0.8, terraformSpeed=0, canResurrect=False)
        if u.get('build'): d['buildOptions'] = u['build']
    if k == 'com':
        d.update(metalMake=2.0, energyMake=30.0, metalStorage=500, energyStorage=800, radarDistance=0, showNanoSpray=True, power=3000, decloakDistance=0,
                 canCloak=False, cloakCost=0, autoHeal=u.get('heal', 0), hideDamage=False, workerTime=u['bp'])
    if k == 'fac':
        d.update(builder=True, workerTime=u['bp'], buildDistance=100, canAssist=False, canReclaim=False, canMove=True, maxVelocity=0, buildOptions=u['build'],
                 yardMap='o' * (u['fp'] ** 2), onoffable=True, activateWhenBuilt=True, canAttack=False, maxSlope=60)
        d['canMove'] = True; d.pop('maxVelocity')
    if k == 'mex':
        d.update(extractsMetal=EXTRACT, extractRange=60, activateWhenBuilt=True, onoffable=True, energyUpkeep=2.0, metalStorage=50, maxSlope=60)
    if k == 'solar': d.update(energyMake=u['energy'], energyStorage=100, activateWhenBuilt=True, maxSlope=60)
    if k == 'heart': d.update(energyMake=u['energy'], energyStorage=500, activateWhenBuilt=True, maxSlope=60)
    if k == 'store': d.update(metalStorage=u['ms'], energyStorage=u['es'], maxSlope=60)
    if k == 'radar': d.update(radarDistance=u['radar'], energyUpkeep=18.0, onoffable=True, activateWhenBuilt=True, maxSlope=60, sonarDistance=0)
    if k in ('def1', 'def2'): d.update(maxSlope=60, fireState=2)
    # weapons
    if u.get('weapons'):
        ws = []
        for i, w in enumerate(u['weapons']):
            w = dict(w); wname = w.pop('name'); key = f"{u['id']}_w{i+1}"
            w.pop('range_dgun', None)
            WEAPONS[key] = dict(name=wname, **w)
            ws.append({'name': key, 'def': key})
        d['weapons'] = ws
    return d

EXTRACT = 0.001
WEAPONS = {}
def write_units():
    for u in UNITS:
        d = unitdef(u)
        txt = '-- Voidborn: %s (%s)\nreturn {\n\t%s = %s,\n}\n' % (u['name'], u['fac'], u['id'], lua(d, 1))
        open(f"{G}/units/{u['id']}.lua", 'w').write(txt)

# ---------------------------------------------------------------- explosion weapondefs
def write_explosions():
    ex = {
     'vb_small': dict(areaOfEffect=36, damage={'default': 55}, edgeEffectiveness=0.2, explosionGenerator='custom:vb_boom_small', impulseFactor=0.3),
     'vb_med':   dict(areaOfEffect=70, damage={'default': 180}, edgeEffectiveness=0.3, explosionGenerator='custom:vb_boom_med', impulseFactor=0.4),
     'vb_big':   dict(areaOfEffect=170, damage={'default': 1400}, edgeEffectiveness=0.35, explosionGenerator='custom:vb_boom_big', impulseFactor=0.5),
    }
    for k, v in ex.items(): v.update(name=k, weaponType='Cannon', range=10, reloadTime=1, weaponVelocity=100)
    allw = dict(ex); allw.update(WEAPONS)
    open(f'{G}/weapons/vb_weapons.lua', 'w').write('-- Voidborn weapon definitions (generated)\nreturn ' + lua(allw) + '\n')

# ---------------------------------------------------------------- CEGs
def ceg(color_start, color_end, size, n, life, spd, flash=True):
    return {
      'usedefaultexplosions': False,
      'flash': dict(air=True, class_='CSimpleGroundFlash', count=1, ground=True, water=True,
                    properties=dict(colormap=f'{color_start}  0 0 0 0', size=size * 1.3, sizegrowth=-0.05, ttl=14, texture='groundflash')),
      'core': dict(air=True, class_='CSimpleParticleSystem', count=1, ground=True, water=True,
                   properties=dict(airdrag=0.9, colormap=f'{color_start}  {color_end}  0 0 0 0', directional=False, emitrot=0, emitrotspread=180,
                                   emitvector='0, 1, 0', gravity='0, 0, 0', numparticles=3, particlelife=10, particlelifespread=4,
                                   particlesize=size, particlesizespread=size * 0.4, particlespeed=0, particlespeedspread=0.5, pos='0, 2, 0',
                                   sizegrowth=1.5, sizemod=1.0, texture='circularthingy', alwaysvisible=False)),
      'sparks': dict(air=True, class_='CSimpleParticleSystem', count=1, ground=True, water=True,
                     properties=dict(airdrag=0.92, colormap=f'{color_start}  {color_end}  0 0 0 0', directional=True, emitrot=45, emitrotspread=40,
                                     emitvector='0, 1, 0', gravity='0, -0.05, 0', numparticles=n, particlelife=int(life), particlelifespread=int(life * 0.5),
                                     particlesize=size * 0.22, particlesizespread=size * 0.1, particlespeed=spd, particlespeedspread=spd * 0.6, pos='0, 2, 0',
                                     sizegrowth=-0.02, sizemod=1.0, texture='flare', alwaysvisible=False)),
    }
def write_effects():
    defs = {
      'vb_choir_hit': ceg('0.6 0.9 1 0.9', '0.5 0.3 1 0.4', 9, 5, 12, 2.5),
      'vb_maw_hit': ceg('0.7 1 0.2 0.9', '1 0.5 0.1 0.4', 9, 5, 12, 2.5),
      'vb_boom_small': ceg('1 0.8 0.5 0.9', '1 0.3 0.1 0.4', 22, 10, 18, 3.5),
      'vb_boom_med': ceg('1 0.85 0.55 0.9', '1 0.35 0.1 0.4', 46, 20, 22, 5.0),
      'vb_boom_big': ceg('1 0.95 0.7 0.95', '1 0.4 0.1 0.5', 110, 44, 30, 8.0),
    }
    out = 'return {\n'
    for name, d in defs.items():
        out += f'\t["{name}"] = {{\n'
        for k, v in d.items():
            if k == 'usedefaultexplosions': out += f'\t\tusedefaultexplosions = false,\n'; continue
            v = dict(v); cls = v.pop('class_')
            props = v.pop('properties')
            out += f'\t\t{k} = {{ air = true, class = "{cls}", count = {v["count"]}, ground = true, water = true, properties = {{\n'
            for pk, pv in props.items():
                out += f'\t\t\t{pk} = {lua(pv)},\n'
            out += '\t\t}, },\n'
        out += '\t},\n'
    out += '}\n'
    open(f'{G}/effects/vb_effects.lua', 'w').write(out)

# ---------------------------------------------------------------- LUS scripts
SPIN_ALWAYS = {'halo': 38, 'petals': 22, 'rings': 25, 'ribs': 12, 'dish': 70, 'fronds': 6, 'crown': 24}
SPIN_ACTIVE = {'spin': 200}
def write_scripts():
    for u in UNITS:
        pcs = meta[u['id']]['pieces']; k = u['kind']
        L = ["-- Voidborn LUS script: %s" % u['id'], "local base = piece 'base'"]
        for p in pcs:
            if p != 'base': L.append(f"local {p} = piece '{p}'")
        L.append("local SIG_AIM = {2, 4, 8, 16}")
        L.append("function script.Create()")
        for p, s in SPIN_ALWAYS.items():
            if p in pcs: L.append(f"\tSpin({p}, y_axis, math.rad({s}))")
        L.append("end")
        if 'spin' in pcs:
            L += ["function script.Activate() Spin(spin, y_axis, math.rad(200), math.rad(40)) end",
                  "function script.Deactivate() StopSpin(spin, y_axis, math.rad(30)) end"]
        for i, w in enumerate(u.get('weapons', []), 1):
            if 'head' in pcs:
                L += [f"function script.AimWeapon{i}(heading, pitch)",
                      f"\tSignal(SIG_AIM[{i}]) SetSignalMask(SIG_AIM[{i}])",
                      "\tTurn(head, y_axis, heading, math.rad(420))",
                      "\tTurn(head, x_axis, -pitch, math.rad(300))",
                      "\tWaitForTurn(head, y_axis) WaitForTurn(head, x_axis)",
                      "\treturn true", "end",
                      f"function script.AimFromWeapon{i}() return head end",
                      f"function script.QueryWeapon{i}() return {'muzzle' if 'muzzle' in pcs else 'head'} end"]
            else:
                L += [f"function script.AimWeapon{i}(heading, pitch) return true end",
                      f"function script.AimFromWeapon{i}() return base end",
                      f"function script.QueryWeapon{i}() return base end"]
            L.append(f"function script.FireWeapon{i}() end")
        if k in ('com', 'con', 'support', 'fac'):
            L += ["local INBUILDSTANCE = (COB and COB.INBUILDSTANCE) or 5",
                  "function script.StartBuilding(heading, pitch) SetUnitValue(INBUILDSTANCE, 1) end",
                  "function script.StopBuilding() SetUnitValue(INBUILDSTANCE, 0) end"]
        if k == 'fac':
            L += ["function script.Activate()",
                  "\tSetUnitValue(COB.YARD_OPEN, 1) SetUnitValue(COB.BUGGER_OFF, 0) SetUnitValue(COB.INBUILDSTANCE, 1)",
                  "end",
                  "function script.Deactivate()",
                  "\tSetUnitValue(COB.INBUILDSTANCE, 0) SetUnitValue(COB.YARD_OPEN, 0) SetUnitValue(COB.BUGGER_OFF, 1)",
                  "end"]
        if 'nano' in pcs: L.append("function script.QueryNanoPiece() return nano end")
        if 'pad' in pcs: L.append("function script.QueryBuildInfo() return pad end")
        L += ["function script.StartMoving() end", "function script.StopMoving() end",
              "function script.Killed(recentDamage, maxHealth) return 1 end"]
        open(f"{G}/scripts/{u['id']}.lua", 'w').write('\n'.join(L) + '\n')

if __name__ == '__main__':
    import sys
    if len(sys.argv) > 1: EXTRACT = float(sys.argv[1])
    write_units(); write_explosions(); write_effects(); write_scripts()
    print('defs written for', len(UNITS), 'units')
