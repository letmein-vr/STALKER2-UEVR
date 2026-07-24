EWidgetInteractionSource =
{
	World                                    = 0,
	Mouse                                    = 1,
	CenterScreen                             = 2,
	Custom                                   = 3,
	EWidgetInteractionSource_MAX             = 4,
}

ECollisionEnabled =
{
	NoCollision                              = 0,
	QueryOnly                                = 1,
	PhysicsOnly                              = 2,
	QueryAndPhysics                          = 3,
	ProbeOnly                                = 4,
	QueryAndProbe                            = 5,
	ECollisionEnabled_MAX                    = 6,
}

ECollisionResponse =
{
	Ignore                                   = 0,
	Overlap                                  = 1,
	Block                                    = 2,
	ECollisionResponse_MAX                   = 3,
}

ECollisionChannel =
{
	ECC_WorldStatic                          = 0,
	ECC_WorldDynamic                         = 1,
	ECC_Pawn                                 = 2,
	ECC_Visibility                           = 3,
	ECC_Camera                               = 4,
	ECC_PhysicsBody                          = 5,
	ECC_Vehicle                              = 6,
	ECC_Destructible                         = 7,
	ECC_EngineTraceChannel1                  = 8,
	ECC_EngineTraceChannel2                  = 9,
	ECC_EngineTraceChannel3                  = 10,
	ECC_EngineTraceChannel4                  = 11,
	ECC_EngineTraceChannel5                  = 12,
	ECC_EngineTraceChannel6                  = 13,
	ECC_GameTraceChannel1                    = 14,
	ECC_GameTraceChannel2                    = 15,
	ECC_GameTraceChannel3                    = 16,
	ECC_GameTraceChannel4                    = 17,
	ECC_GameTraceChannel5                    = 18,
	ECC_GameTraceChannel6                    = 19,
	ECC_GameTraceChannel7                    = 20,
	ECC_GameTraceChannel8                    = 21,
	ECC_GameTraceChannel9                    = 22,
	ECC_GameTraceChannel10                   = 23,
	ECC_GameTraceChannel11                   = 24,
	ECC_GameTraceChannel12                   = 25,
	ECC_GameTraceChannel13                   = 26,
	ECC_GameTraceChannel14                   = 27,
	ECC_GameTraceChannel15                   = 28,
	ECC_GameTraceChannel16                   = 29,
	ECC_GameTraceChannel17                   = 30,
	ECC_GameTraceChannel18                   = 31,
	ECC_OverlapAll_Deprecated                = 32,
	ECC_MAX                                  = 33,
}

EPSCPoolMethod =
{
	None                                     = 0,
	AutoRelease                              = 1,
	ManualRelease                            = 2,
	ManualRelease_OnComplete                 = 3,
	FreeInPool                               = 4,
	EPSCPoolMethod_MAX                       = 5,
}

EAttachLocation =
{
	KeepRelativeOffset                       = 0,
	KeepWorldPosition                        = 1,
	SnapToTarget                             = 2,
	EAttachLocation_MAX                      = 3,
}

ERendererStencilMask =
{
	ERSM_Default                             = 0,
	ERSM_255                                 = 1,
	ERSM_1                                   = 2,
	ERSM_2                                   = 3,
	ERSM_4                                   = 4,
	ERSM_8                                   = 5,
	ERSM_16                                  = 6,
	ERSM_32                                  = 7,
	ERSM_64                                  = 8,
	ERSM_128                                 = 9,
	ERSM_MAX                                 = 10,
}

ETriState = 
{
	DEFAULT									= 1,
	TRUE                                    = 2,
	FALSE                                   = 3,
}

EBoneSpaces =
{
	WorldSpace                               = 0,
	ComponentSpace                           = 1,
	EBoneSpaces_MAX                          = 2,
}

EComponentMobility =
{
	Static                                   = 0,
	Stationary                               = 1,
	Movable                                  = 2,
	EComponentMobility_MAX                   = 3,
};
