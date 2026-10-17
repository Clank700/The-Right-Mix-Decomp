"""Insert documentation comments into src/as2/*.as (comments do not change the compiled bytes)."""
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
OUT = os.path.join(ROOT, 'src', 'as2')

HEADER = ('// {title}\n'
          '//\n'
          '// Deobfuscated source of the original class. Compiles (with tools/as2c, using names.json for the\n'
          '// register assignment of locals) to bytecode that is byte-for-byte identical to the original SWF.\n'
          '// Parameter names (par_*) are part of the compiled bytecode and therefore unchanged.\n')

DOCS = {
    'Cam': (
        'Camera for the bar scene. Eases the world clip towards a target offset and can wobble. In this game the\n'
        '// target is always (0, 0), so the camera never actually moves; the code is a leftover from a larger engine.',
        {
            'Cam': 'par_worldClip: the clip that gets moved around; stage size gives the screen centre.',
            'nudgeWorldView': 'Apply the camera position to the world clip.',
            'nudgeWorldZoom': 'Apply the zoom level to the world clip (both axes).',
            'lockViewToEnt': 'Start tracking an entity (anything with xpos / ypos).',
            'trackEnt': 'Ease the camera towards the tracked entity.',
            'wobble': 'Start a decaying shake of the given magnitude, limited to par_wbConstraint pixels.',
            'update': 'Per-frame: ease towards the target, handle wobble damping, move the world clip.',
        }),
    'Shaker': (
        'The cocktail shaker: how much has been poured, which ingredients, and the points earned so far.',
        {
            'Shaker': 'Create an empty shaker at the given screen position (the splash zone for pouring).',
            'pushFluid': ('Pour par_fluidAmount of an ingredient worth par_pointage points. Counts ingredient variety, tints\n'
                          '   * the final drink for a few signature ingredients, and flags the shaker as full at maxVol.'),
        }),
    'Particle': (
        'One particle: a library symbol with a position, velocity and a lifetime, owned by a particle spawner.',
        {
            'Particle': 'Attach the particle symbol to par_targetClip, optionally tinting it (0 / null = no tint).',
            'updateClip': 'Copy the particle position to its clip.',
            'selfDestruct': 'Remove the particle clip.',
        }),
    'Bottle': (
        'A bottle on the shelf. Clicking fetches it with the barman hand; when released it falls back to its shelf spot.',
        {
            'Bottle': 'Attach the bottle clip at its shelf position and hook up click / hover behaviour.',
            'pushHandAction': 'Toggle between "in the barman\'s hand" and "back on the shelf".',
            'updateClip': 'Copy the bottle position to its clip.',
            'update': 'Per-frame: follow the hand while held, otherwise bounce back onto the shelf.',
        }),
    'Additive': (
        'The ice bucket and the lemon bowl (extends Bottle). The clickable area is a separate "mask" clip.',
        {
            'Additive': 'Create the item clip and its clickable mask clip. Note: super() is called without arguments.',
            'pushHandAction': 'Pick up / put back; picking up also pops a burst of pieces from the linked spawner.',
            'updateClip': 'Copy the item position to its clip.',
            'update': ('Per-frame: follow the hand while held (hidden while the garnish is being served).\n'
                       '   * The bare gotoAndStop(1) in the original compiled to a lone GotoFrame action that has no visible\n'
                       '   * effect; it is written here as the pseudo-function gotoFrame(1).'),
        }),
    'DoubleParticleSpawner': (
        'Emits particles: the pour stream, ice and lemon bursts, serve splashes. (The "double" feature, a second clip per\n'
        '// particle, is switched off by every spawner in this game.)',
        {
            'DoubleParticleSpawner': 'par_* configure position, forces, particle symbol, count, lifetime, damping, velocity spread, mass and flags.',
            'kickUpdate': 'Emit one burst right now, even if pushing is locked.',
            'genRandom': 'Random number in [par_min, par_max).',
            'pushChildDepth': 'Return a depth to the pool.',
            'popChildDepth': 'Take a free depth from the pool.',
            'pushParticle': 'Create one particle with randomised velocity / scale.',
            'attachDouble': 'Attach the optional second "double" clip to a particle (unused in this game).',
            'updateChildParticles': 'Per-frame: move every particle, draw the stream line, retire dead ones, emit new ones.',
            'dismantleSpawner': 'Remove the spawner clips.',
        }),
    'reactionSplashParticleSpawner': (
        'A splash that fires when particles of another spawner fall below a line (extends DoubleParticleSpawner).\n'
        '// Note: the original ran the base constructor with no arguments, so the base fields keep their defaults.',
        {
            'reactionSplashParticleSpawner': 'par_triggeredBy: the spawner whose falling particles trigger this splash.',
            'kickUpdate': 'Arm the splash; it emits on the next update.',
            'checkForTrigger': 'Per-frame: re-lock, then trigger (and play the linked sound) for particles below the line.',
        }),
    'BarmanHand': (
        'The barman\'s hand and arm sleeve: fetches bottles, pours them, returns them and slides off screen.',
        {
            'BarmanHand': 'Create the hand and arm sleeve clips and a table of sine values used for the pouring wobble.',
            'fetchTarget': 'Start reaching for a bottle or additive (or, if one is held, put it back first).',
            'updateClip': 'Position the hand clip and stretch / rotate the arm sleeve from the shoulder to the hand.',
            'easeToTarget': 'Move par_moveObj a fraction par_damping towards the target; true once close enough.',
            'moveHandToGoal': 'Game state getBottle: travel, grab (or return) the item, then retreat to the rest position.',
            'returnToRest': 'Game state rest: hang at the rest position and straighten the held bottle.',
            'returnTweenHand': 'Game state returnTweenHand: slide off the bottom of the screen and lower Miguel\'s arm.',
            'pour': 'Game state pour: tip the bottle over the shaker, or drop in ice / lemon.',
        }),
    'CocktailGame': (
        'The whole game: state machine, shelf layout, controls and the per-frame main loop. States (gameState):\n'
        '// preGame, getBottle, pour, rest, returnTweenHand, shakeRest, shake, serve, serveRest, serveLemon,\n'
        '// finaleInit, finale, endGame, waitInput.',
        {
            'CocktailGame': 'Build the scene: bar, hand, Miguel, shaker, 21 bottles, ice, lemon, particle effects, sounds, buttons and the intro / end screens.',
            'restartGame': '"Back to the bar?": reset the shaker, hand, sounds and screens for a new drink.',
            'swapInfoText': 'Unused (empty in the original).',
            'createUseableDepths': 'Fill a depth pool with the integers par_minDepth..par_maxDepth (popped from the end).',
            'popUseableDepth': 'Take the next free depth.',
            'pushUseableDepth': 'Return a depth to the pool.',
            'randomRange': 'Random integer between min and max.',
            'assembleShop': 'Unused (empty in the original).',
            'placeBottles_set': 'Place the 21 bottles at hand-tuned positions and set their colours, labels and score values.',
            'placeBottles': 'Generic grid layout for bottles (unused; kept from an earlier version).',
            'switchState': 'Change the game state.',
            'updateBottles': 'Update every bottle.',
            'updateDynamics': 'Update every particle spawner and splash.',
            'checkInput': 'Translate the held mouse button + Pour / Shake into state changes.',
            'mainLoop': 'Once per frame (18 fps): run the current state, then update gauge, hand, effects and bottles.',
        }),
    'PIM_Colour': (
        'net.pluginmedia.PIM_Colour: a Color object with helpers to tint a clip (Plugin Media\'s utility class).',
        {
            'PIM_Colour': 'Wrap par target clip.',
            'setTint': 'Blend the clip towards a colour by a percentage (resetMode: start from the untinted state).',
            'setBrightness': 'Lighten (positive) or darken (negative) the clip by a percentage.',
        }),
}


def apply(path, key):
    cls_doc, methods = DOCS[key]
    text = open(path, encoding='utf-8').read()
    # strip old generated comments so the script is idempotent
    text = re.sub(r'^// [^\n]*\n(//[^\n]*\n)*\n?', '', text) if text.startswith('// ') else text
    text = re.sub(r'^[ \t]*/\*\*.*?\*/\n', '', text, flags=re.S | re.M)
    lines = text.split('\n')
    out = []
    for ln in lines:
        m = re.match(r'(\s*)function\s+(\w+)\s*\(', ln)
        if m and m.group(2) in methods:
            ind = m.group(1)
            doc = methods[m.group(2)]
            doc_lines = doc.split('\n')
            out.append(ind + '/**')
            for d in doc_lines:
                out.append(ind + ' * ' + d.strip().lstrip('* ').strip() if d.strip() else ind + ' *')
            out.append(ind + ' */')
        out.append(ln)
    body = '\n'.join(out)
    head = HEADER.format(title=cls_doc.split('\n')[0] if False else key) + '// ' + cls_doc + '\n\n'
    open(path, 'w', encoding='utf-8', newline='\n').write(head + body)


def main():
    for rel, key in (('Cam.as', 'Cam'), ('Shaker.as', 'Shaker'), ('Particle.as', 'Particle'), ('Bottle.as', 'Bottle'),
                     ('Additive.as', 'Additive'), ('DoubleParticleSpawner.as', 'DoubleParticleSpawner'),
                     ('reactionSplashParticleSpawner.as', 'reactionSplashParticleSpawner'),
                     ('BarmanHand.as', 'BarmanHand'), ('CocktailGame.as', 'CocktailGame'),
                     ('net/pluginmedia/PIM_Colour.as', 'PIM_Colour')):
        apply(os.path.join(OUT, rel), key)
    print('documented')


if __name__ == '__main__':
    main()
