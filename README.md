![Stalker 2 VR](https://raw.githubusercontent.com/letmein-vr/STALKER2-UEVR/master/screenshots/B08D89B3-30EA-40B6-B099-712389A9D5B1.png)

## **⚠️ IMPORTANT ⚠️**

S.T.A.L.K.E.R. 2: Heart of Chornobyl

Custom UEVR build from releases page required!

Inject at the Main Menu, after shader compilation has finished.

### **Credits**
Thanks and credits to: Mutar, jbusfield, gwizdek, Holydh and Pande4360, Joeyhodge as well as Praydog of course.

---
## Controls

![Stalker 2 VR](https://raw.githubusercontent.com/letmein-vr/STALKER2-UEVR/master/screenshots/Stalker2Controls.png)

## 🛠 Features

### Physical Controls & Gestures
Perform actions by physically reaching to different parts of your body and squeezing the **Grip** button on the left or right controllers.

| Action | Body Zone | Hand |
| :--- | :--- | :--- |
| **Primary Weapon** | Right shoulder | Right |
| **Secondary Weapon** | Left shoulder | Right |
| **Sidearm** | Right hip | Right |
| **Knife/Melee** | Left hip | Left |
| **Flashlight** | Head | Right |
| **Night Vision** | Head | Left |
| **Inventory** | Right shoulder | Left |
| **Detector** | Right chest | Left |
| **Bolts** | Right chest | Right |
| **Grenades** | Left chest | Right |
| **PDA** | Left chest | Left |
| **Weapon Attachments (default off)** | Left shoulder | Left |

* **D-Pad Controls:** Activate using the **Right Controller Thumb Rest** and **Left Thumbstick**. You can change this via usual UEVR Input tab.
* **Leaning:** Enabled via **Left Trigger**. If movement becomes very slow, Lean is likely toggled on!
* **Haptic Feedback:** Controllers vibrate when successfully interacting with a body zone or the flashlight/NVG.
* **Body Items:** See your grenade, detector, bolt and sidearm on your body at their gesture zones. The sidearm only shows once it has been drawn at least once, and grenades and bolts are only learned from being held.

### Weapon Handling & Combat
* **Manual Reloading:** Reach to the gun magazine with your left hand and press **Left Grip** to eject it, grab a fresh magazine from your left hip, then insert it into the weapon. Enabled by default.
* **Animated Reloading:** Turn **Manual Reload** off in the options menu to use the game's reload animation instead: reach to the gun magazine with your left hand and press **Left Grip**, and the hand follows the animation.
* **Physical Knife Melee:** Swing right controller with knife equipped to melee.
* **Physical Throwing:** Physically throw grenades and bolts by equipping one, holding down **Right Trigger** or **Right Grip** and releasing when you throw. Enabled by default; can be toggled off in the options menu.
* **Two-Handed Aiming:** Hold the **Left Grip** on the weapon barrel or handle to align shots.
* **Physical Recoil:** Firing kicks the VR camera upwards.
* **Interactive ADS:** Bring your weapon up to your HMD and the aim should automatically enter ADS mode. Lowering your weapon will revert. Beware this is experimental! Disabled by default.

### Scopes
* **Activation:** Two-hand the weapon and hold **Right Grip**. The scope appears when within 15cm of your eye.
* **Brightness:** While looking through a scope, hold **Right Grip**, rest your thumb on the **Left Thumb Rest**, and move the **Right Thumbstick** Up/Down.
* **Reflex Scopes:** A dynamic red dot should appear when looking through these and will move based on line of sight through the scope (aiming is NOT perfect).

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

### Cvars Options
* **Cvars:** Tailor your Cvars to your system - includes options for Volumetrics, Shadows, Lighting/Lumen, Foliage/View Distance

## Optional Plugins

* **PipelineRefresh.dll:** Download and copy it to the profile `plugins` folder if you encounter DLSS quarter-eye flashing in the right eye. Credit: **Remleo** (https://github.com/Remleo/uevr-plugins/tree/main)

## Recent Fixes

* Loading saves and/or dying and reloading should no longer crash or softlock the game with the weapon wheel open.

## ⚠️ Known Issues ⚠️

* **VR Hands:** Player knockdowns can cause hands to disappear; reset scripts to fix.
* **Laser Sights:** These are not accurate/aligned.
