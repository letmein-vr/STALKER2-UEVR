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
	ECollisionEnabled_MAX                    = 4,
}

ECollisionResponse =
{
	Ignore                                   = 0,
	Overlap                                  = 1,
	Block                                    = 2,
	ECollisionResponse_MAX                   = 3,
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
