import os as _os
ROOT = _os.path.abspath(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)), ".."))
import os, json, math
G = ROOT + '/game'
meta = json.load(open(ROOT + '/out/meta.json'))

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
def _cp(cp, d):
    if cp: d['customParams'] = dict(cp)
    return d
CEG = {'choir': 'vb_choir_hit', 'maw': 'vb_maw_hit', 'tympan': 'vb_tympan_hit', 'miasma': 'vb_miasma_hit'}
def laser(fac, rng, reload, dmg, rgb, thick=2.0, aoe=8, vel=900, core=0.6, flare=4, burst=1, burstrate=0.1, name='Gaze', cp=None):
    return _cp(cp, dict(name=name, weaponType='LaserCannon', range=rng, reloadTime=reload, damage={'default': dmg}, areaOfEffect=aoe,
                weaponVelocity=vel, rgbColor=rgb, thickness=thick, coreThickness=core, laserFlareSize=flare, duration=0.12,
                explosionGenerator='custom:' + CEG[fac], tolerance=8000, turret=True, avoidFriendly=False, collideFriendly=False,
                collideFeature=False, intensity=0.9, texture1='largebeam', texture2='laserend', texture3='flare',
                texture4='flare', burst=burst, burstRate=burstrate, sprayAngle=200, edgeEffectiveness=0.3, impulseFactor=0.2,
                size=thick))
def beam(fac, rng, dps, rgb, thick=4.5, aoe=12, beamtime=0.85, reload=1.0, name='Gaze'):
    # persistent beam: on its target for most of each cycle; damage is ~per second while the beam is on
    return dict(name=name, weaponType='BeamLaser', range=rng, reloadTime=reload, beamTime=beamtime, beamBurst=False, sweepFire=False,
                damage={'default': dps}, areaOfEffect=aoe, rgbColor=rgb, thickness=thick, coreThickness=0.55, laserFlareSize=8,
                largeBeamLaser=True, tileLength=240, scrollSpeed=6, pulseSpeed=1.2, beamDecay=0.9, targetMoveError=0.05,
                explosionGenerator='custom:' + CEG[fac], tolerance=8000, turret=True, avoidFriendly=False, collideFriendly=False,
                collideFeature=False, intensity=0.9, texture1='largebeam', texture2='laserend', texture3='flare', texture4='flare',
                edgeEffectiveness=0.3, impulseFactor=0.0, size=thick)
def glob(fac, rng, reload, dmg, rgb, vel=280, aoe=44, size=7, name='Acid Spit'):
    # slow, long-range, nearly straight glob (low myGravity): hits hard and splashes, but takes seconds to arrive
    return dict(name=name, weaponType='Cannon', range=rng, reloadTime=reload, weaponVelocity=vel, myGravity=0.02, damage={'default': dmg},
                areaOfEffect=aoe, edgeEffectiveness=0.4, rgbColor=rgb, size=size, sizeDecay=0.0, alphaDecay=1.0, intensity=0.9, stages=6,
                separation=0.7, noGap=False, texture1='circularthingy', texture2='flare', explosionGenerator='custom:' + CEG[fac],
                tolerance=8000, turret=True, avoidFriendly=False, collideFriendly=False, collideFeature=False, sprayAngle=100, impulseFactor=0.3)
def missile(fac, rng, reload, dmg, burst=1, aoe=40, vel=320, color='0.7 1 0.2', name='Spores', cp=None):
    return _cp(cp, dict(name=name, weaponType='MissileLauncher', range=rng, reloadTime=reload, damage={'default': dmg}, areaOfEffect=aoe,
                weaponVelocity=vel, startVelocity=140, weaponAcceleration=160, flightTime=5, tracks=True, turnRate=9000, smokeTrail=True,
                explosionGenerator='custom:' + CEG[fac], turret=True, avoidFriendly=False, collideFriendly=False,
                burst=burst, burstRate=0.18, size=3.0, rgbColor=color, texture1='flare', texture2='smoketrail', cegTag='',
                edgeEffectiveness=0.3, impulseFactor=0.2, tolerance=12000, dance=20, wobble=2500, trajectoryHeight=0.4))
def flame(rng, reload, dmg, name='Maw Breath', cp=None, colors='0.4 1 0.2 0.5  0.9 0.9 0.1 0.3  0.9 0.2 0.0 0.2  0 0 0 0.0'):
    return _cp(cp, dict(name=name, weaponType='Flame', range=rng, reloadTime=reload, damage={'default': dmg}, areaOfEffect=14,
                weaponVelocity=260, sizeGrowth=1.4, size=6, flameGfxTime=1.0, colorMap=colors,
                explosionGenerator='', turret=True, avoidFriendly=False, collideFriendly=False, fireStarter=0,
                tolerance=4000, texture1='flame', impulseFactor=0.0, edgeEffectiveness=0.5))
def dgun(fac, name, rgb):
    return dict(name=name, weaponType='DGun', range=240, reloadTime=1.4, damage={'default': 2600}, areaOfEffect=64, weaponVelocity=320,
                commandFire=True, noAutoTarget=True, noExplode=True, collideFriendly=False, collideFeature=False, avoidFriendly=False, turret=True,
                explosionGenerator='custom:vb_boom_med', rgbColor=rgb, size=22, energyPerShot=500, tolerance=4000,
                texture1='circularthingy', texture2='flare', sprayAngle=0, impulseFactor=0.0, edgeEffectiveness=0.5, fireStarter=100,
                range_dgun=1)


# ---- 0.16: the Tympan Conclave (sound) and the Miasma Bloom (gas).
# customParams on a weapon are read by two new gadgets:
#   vb_resonance = '1'                     (LuaRules/Gadgets/vb_resonance.lua)  a hit on a target that other Tympan weapons hit a moment ago does more damage
#   vb_poison_dps / vb_poison_secs         (LuaRules/Gadgets/vb_miasma.lua)     a hit adds a poison stack and marks (scents) the target
RES = {'vb_resonance': '1'}
def poison(dmg, reload, burst=1, share=0.08, secs=6):
    return {'vb_poison_dps': str(round(dmg * burst / reload * share, 1)), 'vb_poison_secs': str(secs)}
def sonic(fac, rng, reload, dmg, rgb, aoe=40, vel=620, size=9, name='Sonic Wave', imp=0.5):
    # a slow-ish ring of pressure: wide splash, a shove (impulse) and no direct-hit bonus - the damage is in the area
    return dict(name=name, weaponType='Cannon', range=rng, reloadTime=reload, weaponVelocity=vel, myGravity=0.01, damage={'default': dmg},
                areaOfEffect=aoe, edgeEffectiveness=0.55, rgbColor=rgb, size=size, sizeDecay=0.0, alphaDecay=0.9, intensity=0.9, stages=3,
                separation=1.2, noGap=False, texture1='circularthingy', texture2='flare', explosionGenerator='custom:' + CEG[fac],
                tolerance=8000, turret=True, avoidFriendly=False, collideFriendly=False, collideFeature=False, sprayAngle=60, impulseFactor=imp,
                customParams=dict(RES))
def pulse(fac, rng, reload, dmg, rgb, *a, **kw):
    return laser(fac, rng, reload, dmg, rgb, *a, cp=RES, **kw)
def gasshell(fac, rng, reload, dmg, rgb, aoe=60, vel=250, size=8, name='Gas Shell', share=0.08):
    # a heavy bulb of gas on a nearly straight flight; it splashes, and what it touches is poisoned and scented
    return dict(name=name, weaponType='Cannon', range=rng, reloadTime=reload, weaponVelocity=vel, myGravity=0.02, damage={'default': dmg},
                areaOfEffect=aoe, edgeEffectiveness=0.5, rgbColor=rgb, size=size, sizeDecay=0.0, alphaDecay=1.0, intensity=0.9, stages=6,
                separation=0.7, noGap=False, texture1='circularthingy', texture2='flare', explosionGenerator='custom:' + CEG[fac],
                tolerance=8000, turret=True, avoidFriendly=False, collideFriendly=False, collideFeature=False, sprayAngle=120, impulseFactor=0.2,
                customParams=poison(dmg, reload, share=share))
def dart(fac, rng, reload, dmg, rgb, *a, **kw):
    return laser(fac, rng, reload, dmg, rgb, *a, cp=poison(dmg, reload, burst=kw.get('burst', 1)), **kw)
def spore(fac, rng, reload, dmg, burst=1, aoe=40, name='Spores', color='0.85 0.4 1'):
    return missile(fac, rng, reload, dmg, burst=burst, aoe=aoe, color=color, name=name, cp=poison(dmg, reload, burst))
def gasjet(rng, reload, dmg, name='Gas Jet'):
    return flame(rng, reload, dmg, name, cp=poison(dmg, reload, share=0.05),
                 colors='0.9 0.5 1 0.5  0.9 0.9 0.3 0.3  0.5 0.25 0.6 0.2  0 0 0 0.0')
def qgun(fac, rgb):
    return dict(name='Destabilisation Gun', weaponType='Cannon', range=700, reloadTime=8, damage={'default': 1}, areaOfEffect=0, weaponVelocity=420,
                commandFire=True, noAutoTarget=True, paralyzer=True, paralyzetime=9, collideFriendly=False, collideFeature=False, avoidFriendly=False, turret=True,
                explosionGenerator='custom:vb_stunwave', rgbColor=rgb, size=26, energyPerShot=1000, tolerance=4000, texture1='circularthingy',
                texture2='flare', sprayAngle=0, impulseFactor=0.0, edgeEffectiveness=0.5)

# ---------------------------------------------------------------- unit table
# kind: com con scout/raider/assault/art/support/heavy ; fac/mex/solar/heart/store/radar/def1/def2
def U(id, fac, name, desc, kind, m, hp, **kw):
    d = dict(id=id, fac=fac, name=name, desc=desc, kind=kind, m=m, hp=hp); d.update(kw); return d

# ---------------------------------------------------------------- tier 2
# Upgrading a faction's tier 1 factory in place costs this much; the T2 factory unlocks the T2 units
# and (together with them) the unit forge.  The gadget LuaRules/Gadgets/vb_factory_upgrade.lua reads these
# numbers from the factory's customParams, so this is the one place to tune them.
UPGRADE_METAL, UPGRADE_ENERGY, UPGRADE_SECONDS = 2000, 2800, 45
# 0.18: a Tier 2 factory upgrades in place to Tier 3 (same gadget, customParams.upgrade_tier = 3); the T3 lab builds the T3 heavy
UPGRADE3_METAL, UPGRADE3_ENERGY, UPGRADE3_SECONDS = 4500, 7500, 70
T1_CHOIR = ['ch_seer', 'ch_gazer', 'ch_lashling', 'ch_hoplite', 'ch_basilisk', 'ch_weeper', 'ch_colossus']
T1_MAW = ['mw_weaver', 'mw_skitter', 'mw_gnasher', 'mw_ravager', 'mw_spitter', 'mw_nurse', 'mw_leviathan']
T2_CHOIR = ['ch_saccade', 'ch_sclera', 'ch_lance', 'ch_lachryma', 'ch_panopticon']
T2_MAW = ['mw_shear', 'mw_warmaw', 'mw_rupturer', 'mw_midwife', 'mw_devourer']
T1_TYMPAN = ['ty_tuner', 'ty_whisper', 'ty_tinnitus', 'ty_drummer', 'ty_trumpeter', 'ty_lullaby', 'ty_cacophon']
T2_TYMPAN = ['ty_banshee', 'ty_malleus', 'ty_foghorn', 'ty_siren', 'ty_organon']
T1_MIASMA = ['mi_pollinator', 'mi_sniffer', 'mi_sneezer', 'mi_bellows', 'mi_stinkhorn', 'mi_censer', 'mi_proboscis']
T2_MIASMA = ['mi_pollenwing', 'mi_bloomguard', 'mi_fumigator', 'mi_perfumer', 'mi_titanarum']
NEW_FACTIONS = ('tympan', 'miasma')
NEW_PREFIX = ('ty_', 'mi_')        # 0.16: the factions this generator owns; the 0.15 files of choir / maw carry hand edits (see main)

CB = lambda p: [p + x for x in ('siphon', 'sunpetal', 'heart', 'vault', 'watcher', 'stare', 'pillar')]
UNITS = [
 # ---------------- CHOIR OF THE EYE
 U('ch_hierophant', 'choir', 'Hierophant', 'Cyclopean Commander - builds, sees all, burns what it stares at', 'com', 2500, 4200, speed=1.9, alt=45, sight=620,
   build=['ch_womb'] + CB('ch_')[:0] + ['ch_siphon', 'ch_sunpetal', 'ch_heart', 'ch_vault', 'ch_watcher', 'ch_stare', 'ch_pillar'], bp=95, bd=190,
   weapons=[beam('choir', 470, 80, '0.2 0.55 1.0', name='Gaze'), dgun('choir', 'Cataract Stare', '0.5 0.8 1.0')], hover=True),
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
 U('ch_womb', 'choir', 'Iris Womb', 'Factory - the Choir births its army through an unblinking pool', 'fac', 470, 3300, fp=6, build=['ch_seer', 'ch_gazer', 'ch_lashling', 'ch_hoplite', 'ch_basilisk', 'ch_weeper', 'ch_colossus'], bp=100, e=1300, bt=4600, sight=420, up=('ch_womb2', UPGRADE_METAL, UPGRADE_ENERGY, UPGRADE_SECONDS)),
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
   build=['mw_hive', 'mw_extractor', 'mw_sunbloom', 'mw_core', 'mw_cyst', 'mw_sensor', 'mw_spine', 'mw_bastion', 'mw_maw_jaw'], bp=95, bd=190,
   weapons=[glob('maw', 560, 1.5, 150, '0.7 1 0.2'), dgun('maw', 'Devour', '0.6 1 0.1')], hover=True, heal=3),
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
 U('mw_hive', 'maw', 'Brood Hive', 'Factory - a pulsing mound that vomits out the swarm', 'fac', 420, 3500, fp=6, build=['mw_weaver', 'mw_skitter', 'mw_gnasher', 'mw_ravager', 'mw_spitter', 'mw_nurse', 'mw_leviathan'], bp=100, e=1250, bt=4500, sight=420, heal=4, up=('mw_hive2', UPGRADE_METAL, UPGRADE_ENERGY, UPGRADE_SECONDS)),
 U('mw_extractor', 'maw', 'Root Drill', 'Metal extractor - roots that bore into asteroid ore', 'mex', 40, 520, fp=2, e=340, bt=1300, sight=240, heal=1),
 U('mw_sunbloom', 'maw', 'Sunbloom', 'Energy - tentacle anemone feeding on starlight', 'solar', 82, 680, fp=3, e=0, bt=1500, sight=260, energy=22, heal=1),
 U('mw_core', 'maw', 'Heartfire Egg', 'Advanced energy - a caged egg that burns like a star', 'heart', 1050, 3900, fp=5, e=4000, bt=17500, sight=300, energy=500, heal=2),
 U('mw_cyst', 'maw', 'Gut Cyst', 'Storage - swollen sacs for metal and energy', 'store', 180, 2600, fp=4, e=280, bt=3000, sight=260, ms=1500, es=4000, heal=2),
 U('mw_sensor', 'maw', 'Listening Maw', 'Radar - a tall maw that hears the void', 'radar', 58, 450, fp=2, e=500, bt=1800, sight=460, radar=2300, heal=1),
 U('mw_spine', 'maw', 'Tooth Spire', 'Light defence - a fanged stalk that spits acid', 'def1', 90, 1100, fp=2, e=380, bt=2400, sight=540,
   weapons=[laser('maw', 500, 0.45, 19, '0.7 1 0.2', 2.4, 8, name='Acid Spit')], heal=2),
 U('mw_bastion', 'maw', 'Maw Bastion', 'Heavy defence - a titanic maw crowned with spore tubes', 'def2', 520, 5600, fp=4, e=3100, bt=9000, sight=780,
   weapons=[missile('maw', 860, 2.2, 85, burst=3, aoe=50, name='Spore Volley')], heal=4),

 # ================================================================ TIER 2 (needs the upgraded factory)
 # kind = '<role>2' so that tools that look units up by kind (the AI, the hotkeys) never mix tiers up.
 U('ch_womb2', 'choir', 'Great Iris Womb', 'Tier 2 Factory - the upgraded womb; births the Choir\'s elite and unlocks the unit forge', 'fac2', 2470, 7200, fp=6, build=T1_CHOIR + T2_CHOIR, bp=220, e=4100, bt=9000, sight=520, tier=2, up=('ch_womb3', UPGRADE3_METAL, UPGRADE3_ENERGY, UPGRADE3_SECONDS)),
 U('ch_saccade', 'choir', 'Saccade', 'T2 Raider - a dart of fins and one wide eye; its twin pulse stings faster than the eye can follow', 'raider2', 140, 620, speed=5.0, alt=70, sight=520,
   weapons=[laser('choir', 285, 0.35, 9, '0.55 1 1', 1.8, 6, burst=2, burstrate=0.08, name='Saccade Pulse')], tier=2),
 U('ch_sclera', 'choir', 'Sclera Knight', 'T2 Assault - an armoured one-eyed champion behind an iris shield', 'assault2', 520, 4200, speed=1.9, alt=100, sight=560,
   weapons=[laser('choir', 430, 0.6, 78, '0.4 0.9 1', 3.6, 12, name='Knight Gaze'), laser('choir', 330, 0.3, 14, '0.9 0.5 1', 2.0, 6, name='Lash Volley')], tier=2),
 U('ch_lance', 'choir', 'Lidless Lance', 'T2 Artillery - a coiled serpent whose beam reaches across half the rift', 'art2', 640, 1100, speed=1.6, alt=170, sight=900,
   weapons=[laser('choir', 1150, 3.2, 330, '1 0.95 0.5', 3.4, 24, vel=1800, core=0.8, flare=8, name='Lance Beam')], tier=2),
 U('ch_lachryma', 'choir', 'Lachryma', 'T2 Support - a haloed tear-mother; fast builder, rebuilds and mends allies', 'support2', 380, 1800, speed=2.2, alt=115, sight=560, bp=95, bd=210, tier=2),
 U('ch_panopticon', 'choir', 'Panopticon', 'T2 Heavy - the all-seeing flagship; a hundred eyes and a halo that judges', 'heavy2', 4200, 34000, speed=0.85, alt=300, sight=800,
   weapons=[laser('choir', 800, 1.3, 900, '1 0.6 1', 11.0, 70, vel=1500, core=0.9, flare=16, name='Verdict'),
            laser('choir', 480, 0.4, 38, '0.5 1 1', 2.6, 10, burst=2, burstrate=0.1, name='Hundred Eyes')], tier=2),
 U('mw_hive2', 'maw', 'Great Brood Hive', 'Tier 2 Factory - the grown hive; vomits out the swarm\'s elite and unlocks the unit forge', 'fac2', 2420, 7600, fp=6, build=T1_MAW + T2_MAW, bp=220, e=4050, bt=9000, sight=520, heal=8, tier=2, up=('mw_hive3', UPGRADE3_METAL, UPGRADE3_ENERGY, UPGRADE3_SECONDS)),
 U('mw_shear', 'maw', 'Shearwing', 'T2 Raider - four-winged wasp with a flaying breath', 'raider2', 130, 1100, speed=4.4, alt=65, sight=500,
   weapons=[flame(150, 0.1, 9.5)], heal=3, tier=2),
 U('mw_warmaw', 'maw', 'Warmaw', 'T2 Assault - an armoured war-beast; corrosive bolts and a pod of spore-missiles', 'assault2', 480, 5200, speed=1.8, alt=85, sight=540,
   weapons=[laser('maw', 400, 0.65, 105, '1 0.55 0.1', 4.0, 16, name='Siege Bolt'), missile('maw', 380, 1.1, 22, burst=3, aoe=30, name='Spore Pod')], heal=5, tier=2),
 U('mw_rupturer', 'maw', 'Rupturer', 'T2 Artillery - a swollen bile-sac; its salvo bursts over whole squads', 'art2', 620, 1300, speed=1.6, alt=150, sight=900,
   weapons=[missile('maw', 1180, 3.2, 220, burst=2, aoe=90, name='Bile Salvo')], heal=2, tier=2),
 U('mw_midwife', 'maw', 'Midwife', 'T2 Support - brood-tender with a cluster of egg-sacs; fast builder, mends the swarm', 'support2', 360, 2000, speed=2.1, alt=110, sight=520, bp=95, bd=210, heal=6, tier=2),
 U('mw_devourer', 'maw', 'Devourer', 'T2 Heavy - a world-eater behind a gate of teeth', 'heavy2', 3900, 46000, speed=0.8, alt=290, sight=760,
   weapons=[laser('maw', 700, 1.4, 980, '0.7 1 0.1', 14.0, 80, vel=1300, core=1.0, flare=16, name='Maw Cannon'),
            missile('maw', 600, 1.2, 40, burst=5, aoe=34, name='Brood Barrage')], heal=12, tier=2),

 # ================================================================ 0.16  TYMPAN CONCLAVE (the Ear)
 # Sound: wide-splash pressure waves, pulses that add up when the whole conclave aims at one target (Resonance), radar on the units
 # (they hear before they see: short sight, long radar) and ears that give away a cloaked enemy (customParams.hear, in elmos).
 U('ty_auditor', 'tympan', 'Auditor', 'Ear Commander - hears every whisper in the void and answers with a note that breaks stone', 'com', 2500, 4300, speed=1.9, alt=45, sight=480, radar_m=1000, hear=350,
   build=['ty_echo', 'ty_cilia', 'ty_pinna', 'ty_spiral', 'ty_wax', 'ty_pinnamast', 'ty_fork', 'ty_gong'], bp=95, bd=190,
   weapons=[sonic('tympan', 520, 1.5, 130, '1 0.8 0.3', aoe=50, vel=700, size=11, name='Crescendo'), dgun('tympan', 'Perforate', '1 0.85 0.4'), qgun('tympan', '1 0.8 0.35')], hover=True),
 U('ty_tuner', 'tympan', 'Tuner', 'Builder - a floating ear whose cilia tune raw matter into form', 'con', 90, 540, speed=2.7, alt=50, sight=440, radar_m=0,
   build=['ty_echo', 'ty_cilia', 'ty_pinna', 'ty_spiral', 'ty_wax', 'ty_pinnamast', 'ty_fork', 'ty_gong'], bp=70, bd=185),
 U('ty_whisper', 'tympan', 'Whisper', 'Scout - a fluttering ear-wing that hears the enemy long before it sees it', 'scout', 40, 220, speed=5.1, alt=92, sight=400, radar_m=1500, hear=450,
   weapons=[pulse('tympan', 250, 0.5, 6, '1 0.85 0.4', 1.6, 6, name='Tick')]),
 U('ty_tinnitus', 'tympan', 'Tinnitus', 'Raider - a shrill little dart; one is a nuisance, a pack is a ringing that does not stop', 'raider', 54, 360, speed=3.8, alt=65, sight=400,
   weapons=[pulse('tympan', 210, 0.3, 6.4, '1 0.7 0.9', 1.8, 6, name='Whine')]),
 U('ty_drummer', 'tympan', 'Drummer', 'Assault - a bass-drum belly and two mallets; every beat leaves a ring of broken air', 'assault', 190, 1500, speed=2.0, alt=90, sight=460,
   weapons=[sonic('tympan', 360, 0.7, 42, '1 0.75 0.3', aoe=40, vel=560, size=9, name='Bass Wave')]),
 U('ty_trumpeter', 'tympan', 'Trumpeter', 'Artillery - one colossal ear-trumpet turned round: it throws sound across the rift', 'art', 235, 620, speed=1.7, alt=145, sight=520, radar_m=900,
   weapons=[sonic('tympan', 800, 2.2, 100, '1 0.85 0.35', aoe=64, vel=900, size=10, name='Sonic Boom')]),
 U('ty_lullaby', 'tympan', 'Lullaby', 'Support - a drifting conch that hums the wounded whole; hears what is nearby', 'support', 150, 720, speed=2.3, alt=105, sight=420, radar_m=800, hear=300, bp=38, bd=150),
 U('ty_cacophon', 'tympan', 'Cacophon', 'Heavy - a cochlea the size of a cathedral, ringed with horns; its voice flattens whole squads', 'heavy', 1600, 9800, speed=1.05, alt=225, sight=520,
   weapons=[sonic('tympan', 600, 1.3, 300, '1 0.7 0.3', aoe=90, vel=800, size=16, name='Shockwave'),
            pulse('tympan', 380, 0.5, 28, '1 0.7 0.95', 2.2, 10, name='Lesser Voices')]),
 U('ty_echo', 'tympan', 'Echo Chamber', 'Factory - a bell of living flesh; whatever is spoken into it comes out as an army', 'fac', 460, 3300, fp=6, build=['ty_tuner', 'ty_whisper', 'ty_tinnitus', 'ty_drummer', 'ty_trumpeter', 'ty_lullaby', 'ty_cacophon'],
   bp=100, e=1280, bt=4500, sight=380, up=('ty_echo2', UPGRADE_METAL, UPGRADE_ENERGY, UPGRADE_SECONDS)),
 U('ty_cilia', 'tympan', 'Cilia Tap', 'Metal extractor - hair cells that feel ore humming in the asteroid', 'mex', 42, 470, fp=2, e=350, bt=1300, sight=240),
 U('ty_pinna', 'tympan', 'Sun Pinna', 'Energy - a cupped ear that drinks the hum of the stars', 'solar', 84, 600, fp=3, e=0, bt=1500, sight=240, energy=22),
 U('ty_spiral', 'tympan', 'Harmonic Spiral', 'Advanced energy - a cochlea standing on end, ringing the vacuum itself', 'heart', 1080, 3500, fp=5, e=4100, bt=17500, sight=280, energy=500),
 U('ty_wax', 'tympan', 'Wax Vault', 'Storage - sealed chambers of amber cerumen', 'store', 185, 2300, fp=4, e=300, bt=3000, sight=240, ms=1500, es=4000),
 U('ty_pinnamast', 'tympan', 'Auricle Array', 'Radar - a tall stalk and one enormous turning ear; it hears cloaked things breathe', 'radar', 62, 420, fp=2, e=520, bt=1800, sight=360, radar=2800, hear=800),
 U('ty_fork', 'tympan', 'Tuning Fork', 'Light defence - two humming prongs; the note leaves between them', 'def1', 95, 950, fp=2, e=420, bt=2400, sight=440,
   weapons=[pulse('tympan', 520, 0.42, 17, '1 0.85 0.4', 2.0, 8, name='Hum')]),
 U('ty_gong', 'tympan', 'Great Gong', 'Heavy defence - a tower that holds a vast bronze disc; one strike clears a sky', 'def2', 530, 5000, fp=4, e=3200, bt=9300, sight=620,
   weapons=[sonic('tympan', 880, 1.9, 240, '1 0.75 0.3', aoe=80, vel=900, size=14, name='Strike')]),
 U('ty_echo2', 'tympan', 'Grand Echo Chamber', 'Tier 2 Factory - the upgraded chamber; a cathedral of horns that births the conclave\'s elite and unlocks the unit forge', 'fac2', 2450, 7000, fp=6,
   build=T1_TYMPAN + T2_TYMPAN, bp=220, e=4050, bt=9000, sight=440, tier=2, up=('ty_echo3', UPGRADE3_METAL, UPGRADE3_ENERGY, UPGRADE3_SECONDS)),
 U('ty_banshee', 'tympan', 'Banshee', 'T2 Raider - a streamlined scream with swept ear-wings; its burst is three notes too high to bear', 'raider2', 140, 640, speed=5.0, alt=70, sight=420, radar_m=900,
   weapons=[pulse('tympan', 290, 0.35, 6.5, '1 0.6 0.9', 1.8, 6, burst=3, burstrate=0.07, name='Shriek')], tier=2),
 U('ty_malleus', 'tympan', 'Malleus', 'T2 Assault - an armoured champion with a hammer-bone and a drum for a shield', 'assault2', 520, 4300, speed=1.9, alt=100, sight=480,
   weapons=[sonic('tympan', 430, 0.8, 95, '1 0.75 0.3', aoe=50, vel=620, size=11, name='Hammer Blow'), pulse('tympan', 330, 0.3, 14, '1 0.7 0.9', 2.0, 6, name='Anvil Chorus')], tier=2),
 U('ty_foghorn', 'tympan', 'Foghorn', 'T2 Artillery - the longest horn in the rift; its note arrives long after the horn has sounded', 'art2', 650, 1050, speed=1.6, alt=170, sight=560, radar_m=1200,
   weapons=[sonic('tympan', 1150, 3.2, 300, '1 0.85 0.35', aoe=90, vel=1100, size=14, name='Foghorn Blast')], tier=2),
 U('ty_siren', 'tympan', 'Siren', 'T2 Support - a haloed song-conch; fast builder, mends the conclave and hears what hides', 'support2', 380, 1800, speed=2.2, alt=115, sight=460, radar_m=900, hear=400, bp=95, bd=210, tier=2),
 U('ty_organon', 'tympan', 'Organon', 'T2 Heavy - a flying organ; fifteen pipes, one chord, and nothing left standing', 'heavy2', 4200, 35000, speed=0.85, alt=300, sight=640,
   weapons=[sonic('tympan', 780, 1.3, 880, '1 0.7 0.3', aoe=120, vel=1000, size=20, name='Requiem'),
            pulse('tympan', 470, 0.4, 36, '1 0.7 0.95', 2.6, 10, burst=2, burstrate=0.1, name='Hundred Voices')], tier=2),

 # ================================================================ 0.16  MIASMA BLOOM (the Nose)
 # Gas: slow, tough, lingering.  Every hit adds a poison stack (damage over time) and scents the target: a scented enemy stays on the
 # Bloom's map for a while, hidden or not (LuaRules/Gadgets/vb_miasma.lua).  Their Censer sniffs out fallen-unit mushrooms
 # faster (the Censer has a larger reclaim speed than the other tier 1 support units).
 U('mi_rhinarch', 'miasma', 'Rhinarch', 'Nose Commander - a vast drifting snout in a crown of petals; smells fear, breathes out ruin', 'com', 2500, 4700, speed=1.7, alt=45, sight=520,
   build=['mi_nostril', 'mi_truffle', 'mi_lily', 'mi_amber', 'mi_musk', 'mi_scentstalk', 'mi_reek', 'mi_stench'], bp=95, bd=190,
   weapons=[gasshell('miasma', 520, 1.4, 110, '0.85 0.4 1', aoe=70, vel=300, size=9, name='Noxious Breath'), dgun('miasma', 'Asphyxiate', '0.9 0.5 1'), qgun('miasma', '0.85 0.45 1')], hover=True, heal=3),
 U('mi_pollinator', 'miasma', 'Pollinator', 'Builder - a small nostril bloom that sheds spore-threads and knits them into structures', 'con', 88, 600, speed=2.5, alt=50, sight=440,
   build=['mi_nostril', 'mi_truffle', 'mi_lily', 'mi_amber', 'mi_musk', 'mi_scentstalk', 'mi_reek', 'mi_stench'], bp=70, bd=185, heal=1),
 U('mi_sniffer', 'miasma', 'Sniffer', 'Scout - a bobbing snout on a long nose; it tracks what it has tasted', 'scout', 34, 260, speed=5.0, alt=90, sight=680,
   weapons=[dart('miasma', 240, 0.5, 6.5, '0.85 0.5 1', 1.8, 6, name='Spore Dart')], heal=1),
 U('mi_sneezer', 'miasma', 'Sneezer', 'Raider - a puffed bladder with a great twitching nose; one sneeze and everything nearby is sick', 'raider', 52, 620, speed=3.4, alt=60, sight=420,
   weapons=[gasjet(150, 0.1, 4.4)], heal=2),
 U('mi_bellows', 'miasma', 'Bellows', 'Assault - a pleated barrel that heaves gas through a flared snout', 'assault', 170, 2300, speed=1.8, alt=80, sight=460,
   weapons=[gasshell('miasma', 340, 0.7, 44, '0.8 0.5 1', aoe=30, vel=480, size=6, name='Fume Bolt')], heal=3),
 U('mi_stinkhorn', 'miasma', 'Stinkhorn', 'Artillery - an upswept trunk that lobs canisters of reek; the cloud outlasts the blast', 'art', 215, 700, speed=1.6, alt=140, sight=640,
   weapons=[gasshell('miasma', 800, 2.6, 90, '0.8 0.45 1', aoe=100, vel=300, size=9, name='Reek Canister')], heal=1),
 U('mi_censer', 'miasma', 'Censer', 'Support - a swinging thurible of incense; mends the Bloom and sniffs out mushrooms faster', 'support', 150, 820, speed=2.1, alt=100, sight=460, bp=52, bd=150, heal=3),
 U('mi_proboscis', 'miasma', 'Proboscis', 'Heavy - a mile of trunk and a ring of nostrils; the air around it is poison', 'heavy', 1500, 13500, speed=0.95, alt=215, sight=600,
   weapons=[gasshell('miasma', 620, 1.4, 360, '0.8 0.4 1', aoe=90, vel=330, size=14, name='Putrid Cannon'),
            spore('miasma', 520, 1.4, 30, burst=3, aoe=30, name='Spore Cloud')], heal=6),
 U('mi_nostril', 'miasma', 'Nostril Pit', 'Factory - a yawning pair of nostrils that breathe out the swarm', 'fac', 410, 3600, fp=6, build=['mi_pollinator', 'mi_sniffer', 'mi_sneezer', 'mi_bellows', 'mi_stinkhorn', 'mi_censer', 'mi_proboscis'],
   bp=100, e=1230, bt=4400, sight=420, heal=4, up=('mi_nostril2', UPGRADE_METAL, UPGRADE_ENERGY, UPGRADE_SECONDS)),
 U('mi_truffle', 'miasma', 'Truffle Snout', 'Metal extractor - a snout that roots into the asteroid and smells out ore', 'mex', 40, 540, fp=2, e=340, bt=1300, sight=240, heal=1),
 U('mi_lily', 'miasma', 'Sunlily', 'Energy - a scented flower that drinks starlight and breathes perfume', 'solar', 80, 700, fp=3, e=0, bt=1500, sight=260, energy=22, heal=1),
 U('mi_amber', 'miasma', 'Ambergris Core', 'Advanced energy - a congealed lump of perfume that burns like a slow star', 'heart', 1030, 3950, fp=5, e=3950, bt=17200, sight=300, energy=500, heal=2),
 U('mi_musk', 'miasma', 'Musk Sac', 'Storage - a cluster of swollen scent glands holding metal and energy', 'store', 175, 2700, fp=4, e=280, bt=3000, sight=260, ms=1500, es=4000, heal=2),
 U('mi_scentstalk', 'miasma', 'Scent Stalk', 'Radar - a tall stalk crowned with nostril pods that taste the currents of the void', 'radar', 56, 460, fp=2, e=500, bt=1800, sight=460, radar=2300, heal=1),
 U('mi_reek', 'miasma', 'Reek Pod', 'Light defence - a bladder-pod with a short trunk that spits poison darts', 'def1', 88, 1150, fp=2, e=380, bt=2400, sight=540,
   weapons=[dart('miasma', 500, 0.45, 18, '0.85 0.5 1', 2.4, 8, name='Reek Dart')], heal=2),
 U('mi_stench', 'miasma', 'Stench Tower', 'Heavy defence - a trunk-tower crowned with a flared bell that lobs heavy gas', 'def2', 510, 5800, fp=4, e=3100, bt=9000, sight=780,
   weapons=[gasshell('miasma', 860, 2.2, 190, '0.8 0.45 1', aoe=90, vel=330, size=12, name='Stench Shell')], heal=4),
 U('mi_nostril2', 'miasma', 'Great Nostril', 'Tier 2 Factory - the grown pit, a tower of snouts that breathes out the Bloom\'s elite and unlocks the unit forge', 'fac2', 2400, 7800, fp=6,
   build=T1_MIASMA + T2_MIASMA, bp=220, e=4000, bt=9000, sight=520, heal=8, tier=2, up=('mi_nostril3', UPGRADE3_METAL, UPGRADE3_ENERGY, UPGRADE3_SECONDS)),
 U('mi_pollenwing', 'miasma', 'Pollenwing', 'T2 Raider - a quick winged bloom that dusts everything in range with pollen', 'raider2', 128, 1150, speed=4.3, alt=65, sight=500,
   weapons=[gasjet(160, 0.1, 9.5)], heal=3, tier=2),
 U('mi_bloomguard', 'miasma', 'Bloomguard', 'T2 Assault - an armoured flower knight; heavy fume shells and a pod of spore-missiles', 'assault2', 470, 5400, speed=1.8, alt=85, sight=540,
   weapons=[gasshell('miasma', 410, 0.65, 100, '0.8 0.5 1', aoe=40, vel=480, size=8, name='Siege Fume'), spore('miasma', 380, 1.1, 22, burst=3, aoe=30, name='Spore Pod')], heal=5, tier=2),
 U('mi_fumigator', 'miasma', 'Fumigator', 'T2 Artillery - a tank of gas on a trunk as long as a street; the bell lobs a shell that blankets squads', 'art2', 610, 1350, speed=1.6, alt=150, sight=900,
   weapons=[gasshell('miasma', 1180, 3.2, 240, '0.8 0.4 1', aoe=120, vel=380, size=12, name='Fumigation')], heal=2, tier=2),
 U('mi_perfumer', 'miasma', 'Perfumer', 'T2 Support - a bloom hung with censers; fast builder, mends the Bloom and sniffs out mushrooms', 'support2', 350, 2100, speed=2.1, alt=110, sight=520, bp=95, bd=210, heal=6, tier=2),
 U('mi_titanarum', 'miasma', 'Titan Arum', 'T2 Heavy - the corpse flower grown to a monster; its stench is a weapon of its own', 'heavy2', 3800, 48000, speed=0.8, alt=290, sight=760,
   weapons=[gasshell('miasma', 700, 1.4, 960, '0.8 0.4 1', aoe=110, vel=360, size=18, name='Putrefaction'),
            spore('miasma', 600, 1.2, 40, burst=5, aoe=34, name='Corpse Cloud')], heal=12, tier=2),
]
ID = {u['id']: u for u in UNITS}

# ---------------------------------------------------------------- build unitdefs
# zoomed-out icon per role, shared by both factions (the icons are made by tools/gen_icons.py -> game/gamedata/icontypes.lua)
ICON_KINDS = {k: 'vb_' + k for k in ('com', 'con', 'scout', 'raider', 'assault', 'art', 'support', 'heavy', 'fac', 'mex', 'solar',
                                      'heart', 'store', 'radar', 'def1', 'def2')}
T2_KINDS = ('fac2', 'raider2', 'assault2', 'art2', 'support2', 'heavy2', 'fac3', 'heavy3')      # NB: 'def2' (heavy defence) is a T1 kind
def base_kind(k): return k[:-1] if k in T2_KINDS else k
def unitdef(u):
    m = meta[u['id']]; k = u['kind']; fac = u['fac']
    bk = base_kind(k)      # 'raider2' behaves like 'raider'; only customParams.kind keeps the 2
    d = dict(name=u['name'], description=u['desc'], objectName=u['id'] + '.s3o', buildPic=u['id'] + '.png',
             maxDamage=u['hp'], metalCost=u['m'], energyCost=u.get('e', u['m'] * 4), buildTime=u.get('bt', u['m'] * 9),
             sightDistance=u.get('sight', 450), category='VOIDBORN', iconType=ICON_KINDS.get(bk, 'default'), capturable=False, autoHeal=u.get('heal', 0),
             idleAutoHeal=u.get('heal', 0) * 2, idleTime=300, explodeAs='vb_big' if bk in ('heart', 'heavy', 'com') else 'vb_med' if u['m'] > 200 else 'vb_small',
             selfDestructAs='vb_big' if bk in ('heart', 'heavy', 'com') else 'vb_med' if u['m'] > 200 else 'vb_small',
             customParams={'faction': fac, 'kind': k, 'iscommander': 'true' if k == 'com' else 'false'}, corpse='', mass=u['hp'] / 10 + u['m'])
    if u.get('tier'): d['customParams']['tier'] = str(u['tier'])
    if u.get('hear'): d['customParams']['hear'] = str(u['hear'])       # Tympan: enemy cloaks within this many elmos are blown (vb_cloak.lua)
    if u.get('up'):
        d['customParams'].update(upgrade_to=u['up'][0], upgrade_metal=str(u['up'][1]), upgrade_energy=str(u['up'][2]), upgrade_seconds=str(u['up'][3]))
        if u['up'][0].endswith('3'): d['customParams']['upgrade_tier'] = '3'      # 0.18: T2 -> T3 (the gadget's default is 2)
    mobile = bk in ('com', 'con', 'scout', 'raider', 'assault', 'art', 'support', 'heavy')
    if mobile:
        d.update(canMove=True, canFly=True, hoverAttack=True, cruiseAlt=u['alt'], maxVelocity=u['speed'], acceleration=0.06 + 0.08 / (1 + u['m'] / 200),
                 brakeRate=0.25, turnRate=700 if u['m'] < 500 else 400, dontLand=True, airStrafe=False, canSubmerge=False, maxWaterDepth=1000,
                 collide=True, crashDrag=0.02, useSmoothMesh=False, blocking=False, footprintX=2, footprintZ=2, upright=False, canAttack=bool(u.get('weapons')),
                 canPatrol=True, canGuard=True, canRepeat=True, moveState=1, fireState=2 if u.get('weapons') else 0,
                 radarDistance=u.get('radar_m', 0), losEmitHeight=max(20, u['alt']), airSightDistance=u.get('sight', 450))
        d['mass'] = u['m'] + 100
    else:
        d.update(canMove=False, canAttack=bool(u.get('weapons')), blocking=True, upright=True, levelGround=False, footprintX=u['fp'], footprintZ=u['fp'],
                 repairable=True, reclaimable=True, floater=False, movementClass='', stealth=False,
                 crushResistance=100000, mass=100000)
        d.pop('movementClass')
    if bk in ('com', 'con', 'support'):
        d.update(builder=True, workerTime=u['bp'], buildDistance=u['bd'], canReclaim=True, canAssist=True, canRepair=True, repairSpeed=u['bp'],
                 reclaimSpeed=u['bp'] * 0.8, terraformSpeed=0, canResurrect=False)
        if u.get('build'): d['buildOptions'] = u['build']
    if bk == 'com':
        d.update(metalMake=2.0, energyMake=30.0, metalStorage=500, energyStorage=800, radarDistance=u.get('radar_m', 0), showNanoSpray=True, power=3000,
                 autoHeal=u.get('heal', 0), hideDamage=False, workerTime=u['bp'])
    if bk in ('com', 'con'):      # cloakable: vb_cloak.lua toggles it and charges the energy (com 250 E/s, con 100 E/s)
        d.update(decloakDistance=0, canCloak=True, cloakCost=0, cloakCostMoving=0, cloakTimeout=30, initCloaked=False, minCloakDistance=0)
    if bk == 'fac':
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
def write_units(units=None):
    for u in (units or UNITS):
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
    allw = dict(ex); allw.update({k: v for k, v in WEAPONS.items() if not k.startswith(NEW_PREFIX)})
    open(f'{G}/weapons/vb_weapons.lua', 'w').write('-- Voidborn weapon definitions (generated)\nreturn ' + lua(allw) + '\n')

def write_weapons_016():
    # the weapons of the Tympan Conclave and the Miasma Bloom live in their own file (the engine loads every weapons/*.lua)
    w = {k: v for k, v in WEAPONS.items() if k.startswith(NEW_PREFIX)}
    open(f'{G}/weapons/vb_weapons_016.lua', 'w').write('-- Voidborn weapon definitions of the Tympan Conclave and the Miasma Bloom (generated by tools/gen_defs.py)\nreturn ' + lua(w) + '\n')

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
def write_effects(only_new=False):
    defs = {
      'vb_choir_hit': ceg('0.6 0.9 1 0.9', '0.5 0.3 1 0.4', 9, 5, 12, 2.5),
      'vb_maw_hit': ceg('0.7 1 0.2 0.9', '1 0.5 0.1 0.4', 9, 5, 12, 2.5),
      'vb_boom_small': ceg('1 0.8 0.5 0.9', '1 0.3 0.1 0.4', 22, 10, 18, 3.5),
      'vb_boom_med': ceg('1 0.85 0.55 0.9', '1 0.35 0.1 0.4', 46, 20, 22, 5.0),
      'vb_boom_big': ceg('1 0.95 0.7 0.95', '1 0.4 0.1 0.5', 110, 44, 30, 8.0),
    }
    new = {
      'vb_tympan_hit': ceg('1 0.85 0.4 0.9', '0.8 0.45 1 0.4', 12, 6, 12, 2.5),
      'vb_miasma_hit': ceg('0.85 0.45 1 0.9', '0.9 0.9 0.3 0.4', 13, 8, 18, 1.6),
    }
    if only_new: defs = new
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
    open(f'{G}/effects/' + ('vb_effects_016.lua' if only_new else 'vb_effects.lua'), 'w').write(out)

# ---------------------------------------------------------------- LUS scripts
SPIN_ALWAYS = {'halo': 38, 'petals': 22, 'rings': 25, 'ribs': 12, 'dish': 70, 'fronds': 6, 'crown': 24}
SPIN_ACTIVE = {'spin': 200}
def write_scripts(units=None):
    for u in (units or UNITS):
        pcs = meta[u['id']]['pieces']; k = base_kind(u['kind'])
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
            if k == 'com' and i >= 2:
                # the commander's D-gun and Q-gun: the script NEVER reports them as aimed, so the engine cannot fire them on an
                # attack order, as return fire or on its own.  Their only shot is the projectile vb_manualfire.lua spawns on a D / Q click.
                L += [f"function script.AimWeapon{i}(heading, pitch) return false end",
                      f"function script.AimFromWeapon{i}() return {'head' if 'head' in pcs else 'base'} end",
                      f"function script.QueryWeapon{i}() return {'muzzle' if 'muzzle' in pcs else 'base'} end",
                      f"function script.FireWeapon{i}() end"]
                continue
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
    # python3 tools/gen_defs.py            writes the defs, scripts, weapons and effects of the NEW factions (tympan, miasma) only
    # python3 tools/gen_defs.py --all      also rewrites choir and maw.  CAUTION: those files carry hand edits since 0.15 (the Q-gun, the
    #                                      Gaze beam, the Acid Spit glob, cloak flags) that this generator does not know; rerun
    #                                      tools/add_sounds.py afterwards and review the diff.
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if args: EXTRACT = float(args[0])
    if '--all' in sys.argv:
        write_units(); write_explosions(); write_effects(); write_scripts()
    todo = [u for u in UNITS if u['fac'] in NEW_FACTIONS]
    write_units(todo); write_weapons_016(); write_effects(only_new=True); write_scripts(todo)
    print('defs written for', len(UNITS) if '--all' in sys.argv else len(todo), 'units')
