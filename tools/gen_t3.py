#!/usr/bin/env python3
"""0.18 - Tier 3: a Tier 3 lab per faction (the Tier 2 lab upgrades in place, vb_factory_upgrade.lua) and one slow heavy per faction (Choir, Maw, Tympan, Miasma).

Writes ONLY new files (the 5 labs, 5 heavies, their scripts and weapons/vb_weapons_018.lua) and adds the upgrade link to the five
Tier 2 lab unit files.  Nothing else in game/ is rewritten.  Run gen_assets_t3.py first (it makes the models and out/meta.json entries),
then:   python3 tools/gen_t3.py  &&  python3 tools/add_sounds.py

The weapons come from SplinterFaction (CC-BY-SA, github.com/SplinterFaction/SplinterFaction), Loz Alliance / Federation of Kala Tier 3:
  Leviathan     "lasercannon"      a huge, slow-reloading beam laser (reload 7 s, thick, range 2100)  -> every heavy's BEAM (BeamLaser)
                "lightningcannon"  bursts of chained lightning                                         -> every heavy's STORM (LightningCannon)
  Emperor's Scorpion "flakcannon"  a heavy long-range artillery shell                                -> the MORTAR / LANCE / KNELL
  Harbinger     "missile"/"plasmacannon"  salvos of rockets and plasma                               -> the SWARM / STORM missile salvos (Maw, Miasma)
Numbers are rescaled to Voidborn (ranges 380 - 1400, T2 heavies 700 - 800) and given each faction's own twist (resonance, poison, touch).
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_defs as g
from gen_defs import U, laser, beam, glob, missile, sonic, gasshell, spore, lua, RES, poison, CEG

G = g.G

def lightning(fac, rng, reload, dmg, rgb, burst=8, burstrate=0.06, thick=2.6, aoe=14, name='Storm', cp=None, snd=('laser_choir_heavy', 'hit_laser')):
    # SplinterFaction's "lightningcannon": a burst of bolts that strike at once; no travel time, no dodging, shorter range than the beam
    d = dict(name=name, weaponType='LightningCannon', range=rng, reloadTime=reload, damage={'default': dmg}, areaOfEffect=aoe, burst=burst,
             burstRate=burstrate, rgbColor=rgb, thickness=thick, beamTTL=10, duration=1.0, texture1='lightning', intensity=24, laserFlareSize=1,
             explosionGenerator='custom:' + CEG[fac], turret=True, avoidFriendly=False, collideFriendly=False, collideFeature=False,
             avoidFeature=False, edgeEffectiveness=0.5, impulseFactor=0.0, impulseBoost=0, noSelfDamage=True, tolerance=8000, sprayAngle=0)
    if cp: d['customParams'] = dict(cp)
    return d

def heavybeam(fac, rng, dps, rgb, name, cp=None, reload=6.0, beamtime=2.4, thick=9.0, aoe=18):
    # SplinterFaction's Leviathan "lasercannon": a big beam on a long reload.  The damage is per second while the beam is on
    # (same convention as the commanders' Gaze beam, see gen_defs.beam)
    d = beam(fac, rng, dps, rgb, thick=thick, aoe=aoe, beamtime=beamtime, reload=reload, name=name)
    d['coreThickness'] = 0.7; d['laserFlareSize'] = 14
    if cp: d['customParams'] = dict(cp)
    return d

def with_sound(w, start, hit, vol=1.0):
    w = dict(w); w['soundStart'] = 'vb_' + start; w['soundStartVolume'] = vol; w['soundHit'] = 'vb_' + hit; w['soundHitVolume'] = 0.8
    return w

T3_METAL_LAB = 2000 + 0     # (placeholder to keep the table readable; the real lab prices are below)
HEAVY = dict(m=9500, speed=0.48, alt=340)

UNITS = [
 # ---------------------------------------------------------------- labs: T2 lab + UPGRADE3_*; build everything of T1 and T2 plus the T3 heavy
 U('ch_womb3', 'choir', 'Eternal Iris Womb', 'Tier 3 Factory - the womb at the end of sight; it births the Choir\'s elite and the Eidolon', 'fac3', 6970, 11000, fp=6,
   build=g.T1_CHOIR + g.T2_CHOIR + ['ch_eidolon'], bp=320, e=11600, bt=14000, sight=600, tier=3),
 U('mw_hive3', 'maw', 'Primeval Brood Hive', 'Tier 3 Factory - the oldest hive; it vomits out the swarm\'s elite and the Dreadmaw', 'fac3', 6920, 11800, fp=6,
   build=g.T1_MAW + g.T2_MAW + ['mw_dreadmaw'], bp=320, e=11550, bt=14000, sight=600, heal=14, tier=3),
 U('ty_echo3', 'tympan', 'Sanctum Echo Chamber', 'Tier 3 Factory - a cathedral of bells that sings out the conclave\'s elite and the Carillon', 'fac3', 6950, 10800, fp=6,
   build=g.T1_TYMPAN + g.T2_TYMPAN + ['ty_carillon'], bp=320, e=11550, bt=14000, sight=520, tier=3),
 U('mi_nostril3', 'miasma', 'Ancient Nostril', 'Tier 3 Factory - a tower of old snouts that breathes out the Bloom\'s elite and the Rafflesia', 'fac3', 6900, 12000, fp=6,
   build=g.T1_MIASMA + g.T2_MIASMA + ['mi_rafflesia'], bp=320, e=11500, bt=14000, sight=600, heal=14, tier=3),

 # ---------------------------------------------------------------- heavies: slow, enormous, three or four weapons in the SplinterFaction T3 mould
 U('ch_eidolon', 'choir', 'Eidolon', 'T3 Heavy - the Panopticon\'s ghost: two crowns of eyes, a sight that burns for seconds and a lance that reaches across the rift',
   'heavy3', 9600, 90000, speed=0.46, alt=340, sight=900, tier=3,
   weapons=[with_sound(heavybeam('choir', 900, 2400, '1 0.6 1', 'Final Sight'), 'beam_choir', 'hit_beam'),
            with_sound(lightning('choir', 560, 2.5, 130, '0.7 0.9 1', name='Optic Storm'), 'laser_choir_heavy', 'hit_laser'),
            with_sound(laser('choir', 1400, 6.0, 2400, '1 0.95 0.5', 6.0, 60, vel=2200, core=0.9, flare=16, name='Judgement Lance'), 'laser_choir_heavy', 'hit_laser')]),
 U('mw_dreadmaw', 'maw', 'Dreadmaw', 'T3 Heavy - a world-eater with a second ring of fangs; it drowns a front in acid, arcs and a swarm of spore rockets',
   'heavy3', 9200, 115000, speed=0.44, alt=330, sight=860, heal=16, tier=3,
   weapons=[with_sound(heavybeam('maw', 900, 2200, '0.7 1 0.1', 'Gorge Beam'), 'acid_heavy', 'hit_acid'),
            with_sound(lightning('maw', 540, 2.5, 130, '0.7 1 0.3', name='Arc Glands'), 'acid_heavy', 'hit_acid'),
            with_sound(glob('maw', 1300, 5.0, 2600, '0.8 1 0.2', vel=300, aoe=110, size=14, name='Brood Mortar'), 'acid_glob', 'hit_glob'),
            with_sound(missile('maw', 800, 2.4, 60, burst=6, aoe=34, name='Brood Swarm'), 'spore_launch', 'hit_acid')]),
 U('ty_carillon', 'tympan', 'Carillon', 'T3 Heavy - a tower of bells in a ring of bells; one long toll, a storm of static and a knell that flattens a whole squad',
   'heavy3', 9700, 88000, speed=0.46, alt=345, sight=700, tier=3,
   weapons=[with_sound(heavybeam('tympan', 900, 2100, '1 0.8 0.35', 'Great Toll', cp=RES), 'sonic_pulse', 'hit_sonic'),
            with_sound(lightning('tympan', 540, 2.5, 120, '1 0.85 0.4', name='Static Discharge', cp=RES), 'sonic_pulse', 'hit_sonic'),
            with_sound(sonic('tympan', 1300, 5.0, 2400, '1 0.75 0.3', aoe=150, vel=1100, size=22, name='Knell'), 'sonic_boom', 'hit_sonic')]),
 U('mi_rafflesia', 'miasma', 'Rafflesia', 'T3 Heavy - a carrion flower the size of a hill; a ray of rot, spore arcs, a putrid mortar and a storm of spore rockets',
   'heavy3', 9200, 120000, speed=0.44, alt=335, sight=860, heal=16, tier=3,
   weapons=[with_sound(heavybeam('miasma', 900, 2000, '0.85 0.45 1', 'Corpse Ray', cp=poison(2000, 1.0, share=0.05)), 'gas_heavy', 'hit_gas'),
            with_sound(lightning('miasma', 540, 2.5, 130, '0.85 0.6 1', name='Spore Arc', cp=poison(130, 2.5, burst=8)), 'gas_heavy', 'hit_gas'),
            with_sound(gasshell('miasma', 1300, 5.0, 2400, '0.8 0.4 1', aoe=130, vel=320, size=16, name='Putrid Mortar'), 'gas_heavy', 'hit_gas'),
            with_sound(spore('miasma', 800, 2.6, 55, burst=8, aoe=34, name='Spore Storm'), 'spore_launch', 'hit_gas')]),
]

# the weapons keep their sound fields: gen_defs.unitdef() copies the dicts as they are
def main():
    g.UNITS.extend(UNITS)
    g.ID.update({u['id']: u for u in UNITS})
    g.write_units(UNITS)
    g.write_scripts(UNITS)
    # weapons/vb_weapons_018.lua (the engine loads every weapons/*.lua)
    w = {k: v for k, v in g.WEAPONS.items() if k.startswith(('ch_', 'mw_', 'ty_', 'mi_')) and any(k.startswith(u['id'] + '_w') for u in UNITS)}
    open(f'{G}/weapons/vb_weapons_018.lua', 'w').write('-- Voidborn weapon definitions of the Tier 3 heavies (generated by tools/gen_t3.py)\nreturn ' + lua(w) + '\n')
    # the unit files of the other generators carry  script = "<id>.lua"  (unit and each weapon); do the same here
    for u in UNITS:
        p = f"{G}/units/{u['id']}.lua"; t = open(p).read()
        t = t.replace('\t\tname = "%s",\n' % u['name'], '\t\tname = "%s",\n\tscript = "%s.lua",\n' % (u['name'], u['id']), 1)
        t = re.sub(r'(\t\t\t\tname = "[^"]+",\n)(\t\t\t\tdef = )', lambda m: m.group(1) + '\tscript = "%s.lua",\n' % u['id'] + m.group(2), t)
        open(p, 'w').write(t)
    # link each Tier 2 lab to its Tier 3 lab (the unit files of the five factions are hand-patched; only these customParams are added)
    for old, new in (('ch_womb2', 'ch_womb3'), ('mw_hive2', 'mw_hive3'), ('ty_echo2', 'ty_echo3'), ('mi_nostril2', 'mi_nostril3')):
        p = f'{G}/units/{old}.lua'; t = open(p).read()
        if 'upgrade_to' in t: continue
        add = ('\t\t\tupgrade_to = "%s",\n\t\t\tupgrade_metal = "%d",\n\t\t\tupgrade_energy = "%d",\n\t\t\tupgrade_seconds = "%d",\n\t\t\tupgrade_tier = "3",\n'
               % (new, g.UPGRADE3_METAL, g.UPGRADE3_ENERGY, g.UPGRADE3_SECONDS))
        assert '\t\t\ttier = "2",\n' in t, old
        open(p, 'w').write(t.replace('\t\t\ttier = "2",\n', '\t\t\ttier = "2",\n' + add, 1))
    print('wrote %d units, %d weapons' % (len(UNITS), len(w)))

if __name__ == '__main__': main()
