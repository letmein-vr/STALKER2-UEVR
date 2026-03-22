# ☢️ **Stalker 2 UEVR Mod - Player Guide** ☢️

Welcome to the Zone, Stalker! This mod transforms Stalker 2 into an immersive VR experience, and is built on the fantastic original mod by Mutar!

## **⚠️ IMPORTANT ⚠️**

STALKER 2 STEAM VERSION 1.6 REQUIRED! UEVR will crash on any later version of the game!

LATEST UEVR NIGHTLY REQUIRED!

### **Credits**
Thanks and credits to: Mutar, jbusfield, gwizdek, Holydh and Pande4360

---

## 🛠 FEATURES

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
| **Inventory** | Left shoulder | Left |
| **Detector** | Right chest | Left |
| **Bolts** | Right chest | Right (Head Aimed) |
| **Grenades** | Left chest | Left |
| **PDA** | Left chest | Right |
| **Weapon Attachments (default off)** | Left shoulder | Left |

> **Note:** The mod automatically adjusts these zones depending on whether you play seated or standing.

* **D-Pad Controls:** Activate using the **Right Controller Thumb Rest** and **Left Thumbstick**. You can change this via usual UEVR Input tab.
* **Leaning:** Enabled via **Left Trigger**. If movement becomes very slow, Lean is likely toggled on!
* **Haptic Feedback:** Controllers vibrate when successfully interacting with a body zone or the flashlight/NVG.

### Weapon Handling & Combat
* **Reloading:** Reach to the gun magazine with your left hand and press **Left Grip**. The hand will follow the reload animation via collision boxes.
* **Two-Handed Aiming:** Hold the **Left Grip** on the weapon barrel or handle to align shots.
* **Virtual Gunstock (ADS):** Scoped weapons create a "virtual shoulder" to stabilize your view.
* **Physical Recoil:** Firing physically kicks the VR camera upwards.
* **Interactive ADS:** Bring your weapon up to your HMD and the aim should automatically enter ADS mode. Lowering your weapon will revert. Beware this is experimental!

### Scopes
* **Activation:** Two-hand the weapon and hold **Right Grip**. The scope appears when within 15cm of your eye.
* **Brightness:** While looking through a scope, hold **Right Grip**, rest your thumb on the **Left Thumb Rest**, and move the **Right Thumbstick** Up/Down.

### Immersive Animations & VR Hands
* **Dynamic Grip:** Fingers automatically curl to the unique shape of weapons, bolts, or scanners.
* **Animation Sync:** VR hands automatically sync when performing actions like attaching silencers or scopes.
* **Consumables/Ladders/PDA:** VR hands disappear and the full body becomes visible during these animations.
* **VR Hand Shadows:** Enables dynamic shadows for VR Hands (disabled by default).

### Menus & Cutscenes
* **Static UI:** Menus, NPC conversations, and in-game cutscenes anchor in front of you to prevent head-sway.
* **Note:** Cutscene anchoring can be jarring!
* **2D Cutscene Toggle:** Experimental toggle option for 2D Screen cutscenes (tested on Quest 3 with Virtual Desktop only)

### Cvars Options
* **Cvars:** Tailor your Cvars to your system - includes options for Volumetrics, Shadows, Lighting/Lumen, Foliage/View Distance

---

## ⚠️ KNOWN ISSUES ⚠️

* **VR Hands:** Player knockdowns can cause hands to disappear; reset scripts to fix.
* **Holographic Scopes:** Original reticule and scope glass removed, replaced with custom red dot due to upscaling graphical issues.
* **Laser Sights:** These are not accurate/aligned properly.
* **Upscaling Glitch:** Upscaling may cause flickering or screen squashing.
    * **Fix:** Set `r.TemporalAA.Upsampling = 0` in UEVR Cvars, or turn on the Flashlight, or restart.
* **Pre-rendered Cutscenes:** These stay on a 2D screen that follows your head movement.
* **Aim Assist:** Manually **DISABLE** this in game settings every time you load a save.
