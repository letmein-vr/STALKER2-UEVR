![Stalker 2 VR](https://raw.githubusercontent.com/letmein-vr/STALKER2-UEVR/master/screenshots/B08D89B3-30EA-40B6-B099-712389A9D5B1.png)

## **⚠️ IMPORTANT ⚠️**

S.T.A.L.K.E.R. 2: Heart of Chornobyl

Custom UEVR build from releases page required!

Inject at the Main Menu, after shader compilation has finished.

The profile's `plugins` folder must contain the latest `stalker2_uevr.dll` (aim fix) - it is included in the release zip.

### **Credits**
Thanks and credits to: Mutar, jbusfield, gwizdek, Holydh and Pande4360, Joeyhodge as well as Praydog of course.

---
## Controls

![Stalker 2 VR](https://raw.githubusercontent.com/letmein-vr/STALKER2-UEVR/master/screenshots/Stalker2Controls.png)

* **X / B Swap:** X and B are swapped by default; toggle with **Swap X and B Buttons** in the options menu.

## 🛠 Features

### Physical Controls & Gestures
Perform actions by physically reaching to different parts of your body and squeezing the **Grip** button on the left or right controllers. Every gesture can be toggled in the **Gestures Toggles** menu.

| Action | Body Zone | Hand |
| :--- | :--- | :--- |
| **Primary Weapon** | Right shoulder | Right |
| **Secondary Weapon** | Left shoulder | Right |
| **Sidearm** | Right hip | Right |
| **Flashlight** | Head | Right |
| **Night Vision** | Head | Left |
| **Inventory** | Right shoulder | Left |
| **Detector** | Right chest | Left |
| **Bolts** | Right chest | Right |
| **Grenades** | Left chest | Right |
| **PDA** | Left chest | Left |
| **Fresh Magazine / Shells (manual reload)** | Left hip | Left |
| **Fire Mode Switch** | Left hand just above your right hand on the weapon | Left |
| **Weapon Attachments (default off)** | Left shoulder | Left |

* **Escape / Pause (default off):** Touch the **Right Thumb Rest** and click the **Left Thumbstick**.
* **D-Pad Controls:** Activate using the **Right Controller Thumb Rest** and **Left Thumbstick**. You can change this via usual UEVR Input tab.
* **Leaning:** Enabled via **Left Trigger**. If movement becomes very slow, Lean is likely toggled on!
* **Haptic Feedback:** Controllers vibrate when successfully interacting with a body zone or the flashlight/NVG.
* **Body Items:** See your grenade, detector, bolt, sidearm and spare magazine on your body at their gesture zones. They hide while climbing and during scripted animations. The sidearm only shows once it has been drawn at least once, and grenades and bolts are only learned from being held.

### Weapon Handling & Combat
* **Aim Down the Barrel:** Shots travel down the weapon's barrel, not from your head (`stalker2_uevr.dll`). The plugin finds the game's aim function by itself, so it should keep working after game patches.
* **Manual Reloading:** Enabled by default.
  * Reach to the gun magazine with your left hand and press **Left Grip** to eject it.
  * Grab a fresh magazine from the pouch on your left hip and push it into the magwell; release **Left Grip** and it glides home.
  * How close the magazine must be to the magwell is set with **Insert Distance** (Debug Dev Config > Mag Reload Box Sizes & Offsets).
* **Rack to Chamber:** After an empty reload, grab the slide / bolt / charging handle with **Left Grip** and pull it back. On pistols with the slide locked back you can also press **X** to drop the slide. Can be turned off per weapon type, and the grab distance set with **Rack Grab Radius**, in the options menu.
* **Shotguns:** Grab shells one at a time from your left hip and push them into the loading port.
* **Rhino Revolver:** Insert the speedloader, then flick your right hand to close the cylinder.
* **Animated Reloading:** Turn **Manual Reload** off in the options menu to use the game's reload animation instead: reach to the gun magazine with your left hand and press **Left Grip**, and the hand follows the animation.
* **Physical Knife Melee:** Swing right controller with knife equipped to melee.
* **Physical Throwing:** Physically throw grenades and bolts by equipping one, holding down **Right Trigger** or **Right Grip** and releasing when you throw. Enabled by default; can be toggled off in the options menu.
* **Two-Handed Aiming:** Hold the **Left Grip** on the weapon barrel or handle to align shots.
* **Physical Recoil (default off):** Firing kicks the VR camera upwards.
* **Muzzle Flashes:** Line up with the barrel.
* **Interactive ADS:** Bring your weapon up to your HMD and the aim should automatically enter ADS mode. Lowering your weapon will revert. Beware this is experimental! Disabled by default.

### Items & Binoculars
* **Physical Item Pickup:** Put your left hand on an item in the world and hold **Left Grip** to pick it up; let go to drop it. Release it over your left shoulder to put it in your inventory (can be turned off in Gestures Toggles).
* **Binoculars:** Both lenses show a magnified view; raise them to your eyes to look through. Click the **Right Thumbstick** to cycle zoom.

### Scopes
* **PiP Scopes:** Picture-in-picture scope lenses; can be turned off in the options menu.
* **Activation:** Two-hand the weapon and hold **Right Grip**. The scope appears when within 15cm of your eye.
* **Brightness:** While looking through a scope, hold **Right Grip**, rest your thumb on the **Left Thumb Rest**, and move the **Right Thumbstick** Up/Down.
* **Reflex Scopes:** Enable **Custom Red Dot Reticule** in the options menu (off by default) for a dynamic red dot that moves with your line of sight through the scope (aiming is NOT perfect). Russian collimator scopes always show a red dot through clear glass.

### Immersive Animations & VR Hands
* **Dynamic Grip:** Fingers automatically curl to the unique shape of weapons, bolts, or scanners.
* **Animation Sync:** VR hands automatically sync when performing actions like attaching silencers or scopes.
* **Consumables/Ladders/PDA:** VR hands disappear and the full body becomes visible during these animations.
* **VR Hand Shadows:** Enables dynamic shadows for VR Hands (disabled by default).

### IK Arms & Full Body
* **Arms Mode:** Choose between **Hands** and **IK Arms** in the options menu; in IK Arms mode you can also enable **IK Full Body** to show the body and legs (experimental).
* **Locked Weapons:** In IK modes, weapons and attachments are locked to each hand with zero drift.
* **Positioning:** Updated positioning of IK arms and shoulders, with sliders for the experimental full body mode (shoulder smoothing, height, width and forward).

### Menus & Cutscenes
* **Static UI:** Menus, NPC conversations, and in-game cutscenes anchor in front of you to prevent head-sway.
* **Note:** Cutscene anchoring can be jarring!
* **2D Cutscene Toggle:** Experimental toggle option for 2D Screen cutscenes (tested on Quest 3 with Virtual Desktop only)
* **Hide HUD:** Option to hide the game HUD.
* **Sitting Experience:** Option that moves the body gesture zones for playing seated.

### Cvars Options
* **Cvars:** Tailor your Cvars to your system - includes options for Volumetrics, Shadows, Lighting/Lumen, Foliage/View Distance, DLSS rain/puddle artifacts and eye adaptation

## Optional Plugins

* **PipelineRefresh.dll:** Download and copy it to the profile `plugins` folder if you encounter DLSS quarter-eye flashing in the right eye. Credit: **Remleo** (https://github.com/Remleo/uevr-plugins/tree/main)

## ⚠️ Known Issues ⚠️

* **VR Hands:** Player knockdowns can cause hands to disappear; reset scripts to fix.

---
## Repository

* `artifact/` - the UEVR profile (`Stalker2-Win64-Shipping`): scripts, data, plugins and UEVR config. Releases zip this folder.
* `src/` - source of `stalker2_uevr.dll` (aim fix plugin).

### Building the plugin

```
git clone --recursive https://github.com/letmein-vr/STALKER2-UEVR.git
cmake -B build -G "Visual Studio 18 2026" -A x64
cmake --build build --config Release
```

The build copies `stalker2_uevr.dll` into `%APPDATA%\UnrealVRMod\Stalker2-Win64-Shipping\plugins`.
