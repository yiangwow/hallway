LIGHTFAST

Unzip anywhere and run hallway.exe. Needs a Vulkan-capable GPU (any GPU from
the last ~8 years). Windows SmartScreen may warn because the exe is unsigned -
"More info" > "Run anyway".

WASD    walk            mouse   look
Tab     the reading     E       hold to do a thing
C       your list       L       the lamp, once you have it
Esc     free the mouse  Shift   run

You are the last caretaker. Close the house by the list.

To meet the thing now: run from a terminal
  hallway.exe -- --chores=2 --pos=2.4,0.95,0 --yaw=0
then press Tab. It sits in the sun on the far wall of the right-hand room, to your right.

To start at a later beat (the earlier chores done, the sun where they leave it):
  beat                                   run
  C2  sheets over the left room's racks  hallway.exe -- --chores=1 --pos=-2.4,0.95,0 --yaw=90
  C3  the right room's three cranks      hallway.exe -- --chores=2 --pos=2.4,0.95,0 --yaw=-90
  C4  the lamp, the boiler valve         hallway.exe -- --chores=3 --pos=-0.9,0.95,-10.6 --yaw=0   (the hook on the wall ahead, left of the door)
  C5  the left room's cranks, riding     hallway.exe -- --chores=4 --lamp=1 --pos=-2.4,0.95,0 --yaw=90
  C6  the sample card, centre rack       hallway.exe -- --chores=5 --lamp=1 --pos=-8.5,0.95,-2.5 --yaw=0
  C7  hang the lamp, sign the log        hallway.exe -- --chores=6 --lamp=0 --pos=0,0.95,13 --yaw=180
--lamp=1 carries the lamp lit, --lamp=0 carries it unlit; without it the lamp is
where play leaves it (on its hook until C4, in your hand after, on the desk after C7).
