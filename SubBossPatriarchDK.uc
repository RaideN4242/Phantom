class SubBossPatriarchDK extends HardPat;

var bool bHasBoss;

function ClawDamageTarget()
{
	local vector PushDir;
	local name Anim;
	local float frame,rate;
	local float UsedMeleeDamage;
	local bool bDamagedSomeone;
	local KFHumanPawn P;
	local Actor OldTarget;

	if(MeleeDamage > 1)
		UsedMeleeDamage =(MeleeDamage -(MeleeDamage * 0.05))+(MeleeDamage *(FRand()* 0.1));
	else
		UsedMeleeDamage=MeleeDamage;

	GetAnimParams(1, Anim,frame,rate);
	MeleeRange=ClawMeleeDamageRange;

	if(Controller!=none && Controller.Target!=none)
		PushDir =(damageForce * Normal(Controller.Target.Location - Location));
	else
		PushDir=damageForce * vector(Rotation);
	//Flame. Damage to turrets and other actors
	if(!Controller.Target.IsA('KFHumanPawn'))
		MeleeDamageTarget(UsedMeleeDamage, PushDir);
	//
// Begin Balance Round 1(damages everyone in Round 2 and added seperate code path for MeleeImpale in Round 3)
	OldTarget=Controller.Target;
	foreach DynamicActors(class'KFHumanPawn', P)
	{
		if((P.Location - Location)dot PushDir > 0.0)// Added dot Product check in Balance Round 3
		{
			Controller.Target=P;
			bDamagedSomeone=bDamagedSomeone || MeleeDamageTarget(UsedMeleeDamage, damageForce * Normal(P.Location - Location)); // Always pushing players away added in Balance Round 3
		}
	}
	Controller.Target=OldTarget;
	MeleeRange=Default.MeleeRange;
// End Balance Round 1, 2, and 3

	if(bDamagedSomeone)
		PlaySound(MeleeAttackHitSound, SLOT_Interact, 2.0);
}


function bool MakeGrandEntry()
{
	return false; // никаких роликов о появлении патриарха. Это не финальная волна, и он появится незамеченным.
}

State Escaping
{
	function BeginHealing()
	{
		Destroyed();
		Destroy(); // вместо того чтобы похилиться, он исчезает с карты.
	}
}

function Died(Controller Killer, class<DamageType> damageType, vector HitLocation)
{
	Super(KFMonster).Died(Killer,damageType,HitLocation); // По идее его не должны убить, но если уж случится, не должно быть никаких зед таймов и видов сбоку.
}

simulated function PostBeginPlay()
{
	Super.PostBeginPlay();
	
	HealingLevels[0] = Health * 0.00; // Начнёт убегать, когда отнимут 100% хп.
	HealingLevels[1] = Health * 0.00;
	HealingLevels[2] = Health * 0.00;
}

function TakeDamage( int Damage, Pawn InstigatedBy, Vector Hitlocation, Vector Momentum, class<DamageType> damageType, optional int HitIndex)
{
	local float DamagerDistSq;
	local float UsedPipeBombDamScale;
	local KFHumanPawn P;
	local int NumPlayersSurrounding;
	local bool bDidRadialAttack;
	local float HeadShotCheckScale;

	    HeadShotCheckScale *= 1.5;

    // Do larger headshot checks if it is a melee attach
    if( class<KFProjectileWeaponDamageType>(damageType) != none )
    {
        HeadShotCheckScale *= 1.5;
    }
	
	
    //log(GetStateName()$" Took damage. Health="$Health$" Damage = "$Damage$" HealingLevels "$HealingLevels[SyringeCount]);

    // Check for melee exploiters trying to surround the patriarch
    if( Level.TimeSeconds - LastMeleeExploitCheckTime > 1.0 && (class<DamTypeMelee>(damageType) != none
        || class<KFProjectileWeaponDamageType>(damageType) != none) )
    {
        LastMeleeExploitCheckTime = Level.TimeSeconds;
        NumLumberJacks = 0;
        NumNinjas = 0;

		foreach DynamicActors(class'KFHumanPawn', P)
		{
            // look for guys attacking us within 3 meters
            if ( VSize(P.Location - Location) < 150 )
			{
				NumPlayersSurrounding++;

                if( P != none && P.Weapon != none )
                {
                    if( Axe(P.Weapon) != none || Chainsaw(P.Weapon) != none )
                    {
                        NumLumberJacks++;
                    }
                    else if( Katana(P.Weapon) != none )
                    {
                        NumNinjas++;
                    }
                }

				if( !bDidRadialAttack && NumPlayersSurrounding >= 3 )
				{
                    bDidRadialAttack = true;
                    GotoState('RadialAttack');
                    break;
                }
			}
		}
    }

    if ( class<DamTypeCrossbow>(damageType) == none && class<DamTypeCrossbowHeadShot>(damageType) == none )
    {
    	bOnlyDamagedByCrossbow = false;
    }

    // Scale damage from the pipebomb down a bit if lots of pipe bomb damage happens
    // at around the same times. Prevent players from putting all thier pipe bombs
    // in one place and owning the patriarch in one blow.
	if ( class<DamTypePipeBomb>(damageType) != none )
	{
	   UsedPipeBombDamScale = FMax(0,(1.0 - PipeBombDamageScale));

	   PipeBombDamageScale += 0.075;

	   if( PipeBombDamageScale > 1.0 )
	   {
	       PipeBombDamageScale = 1.0;
	   }

	   Damage *= UsedPipeBombDamScale;
	}

    Super(KFMonster).TakeDamage(Damage,instigatedBy,hitlocation,Momentum,damageType);

    if( Level.TimeSeconds - LastDamageTime > 10 )
    {
        ChargeDamage = 0;
    }
    else
    {
        LastDamageTime = Level.TimeSeconds;
        ChargeDamage += Damage;
    }

    if( ShouldChargeFromDamage() && ChargeDamage > 200 )
    {
        // If someone close up is shooting us, just charge them
        if( InstigatedBy != none )
        {
            DamagerDistSq = VSizeSquared(Location - InstigatedBy.Location);

            if( DamagerDistSq < (700 * 700) )
            {
                SetAnimAction('transition');
        		ChargeDamage=0;
        		LastForceChargeTime = Level.TimeSeconds;
        		GoToState('Charging');
        		return;
    		}
        }
    }
    if(Health<=0 || IsInState('RadialAttack'))
        Return;
}

state FireMissile
{
	function RangedAttack(Actor A)
	{
		if( SyringeCount>=2 )
		{
			Controller.Target = A;
			Controller.Focus = A;
		}
	}
	function BeginState()
	{
		MissilesLeft = SyringeCount+Rand(SyringeCount);
		Acceleration = vect(0,0,0);
	}

	function AnimEnd( int Channel )
	{
		local vector Start;
		local Rotator R;

		Start = GetBoneCoords('tip').Origin;
		if( Controller.Target==None )
			Controller.Target = Controller.Enemy;

		if ( !SavedFireProperties.bInitialized )
		{
			SavedFireProperties.AmmoClass = MyAmmo.Class;
			SavedFireProperties.ProjectileClass = Class'BossLAWProj';
			SavedFireProperties.WarnTargetPct = 0.15;
			SavedFireProperties.MaxRange = 10000;
			SavedFireProperties.bTossed = False;
			SavedFireProperties.bLeadTarget = True;
			SavedFireProperties.bInitialized = true;
		}
		SavedFireProperties.bInstantHit = (SyringeCount<1);
		SavedFireProperties.bTrySplash = (SyringeCount>=2);

		R = AdjustAim(SavedFireProperties,Start,100);
		PlaySound(RocketFireSound,SLOT_Interact,2.0,,TransientSoundRadius,,false);
		Spawn(Class'BossLAWProj',,,Start,R);

		bShotAnim = true;
		Acceleration = vect(0,0,0);
		SetAnimAction('FireEndMissile');
		HandleWaitForAnim('FireEndMissile');

		// Randomly send out a message about Patriarch shooting a rocket(5% chance)
		if ( FRand() < 0.05 && Controller.Enemy != none && PlayerController(Controller.Enemy.Controller) != none )
		{
			PlayerController(Controller.Enemy.Controller).Speech('AUTO', 10, "");
		}

		if( MissilesLeft==0 )
			GoToState('');
		else
		{
			--MissilesLeft;
			GoToState(,'SecondMissile');
		}
	}
Begin:
	while ( true )
	{
		Acceleration = vect(0,0,0);
		Sleep(0.1);
	}
SecondMissile:
	Acceleration = vect(0,0,0);
	Sleep(0.5f);
	AnimEnd(0);
}

function float NumPlayersHealthModifer() // Свои отдельные настройки хп в зависимости от игроков.
{
	local float AdjustedModifier;
	local int NumEnemies,CurLevel;
	local Controller C;

	AdjustedModifier = 0.0;

	For( C=Level.ControllerList; C!=None; C=C.NextController )
	{
		if( C.bIsPlayer && C.Pawn!=None && C.Pawn.Health > 0 )
		{
			NumEnemies++;
			CurLevel = KFPlayerReplicationInfo(C.PlayerReplicationInfo).ClientVeteranSkillLevel;
			if ( CurLevel < 9 )
			{
				AdjustedModifier += 1.0;
			}
			else if ( CurLevel < 10 )
			{
				AdjustedModifier += 1.1;
			}
			else if ( CurLevel < 11 )
			{
				AdjustedModifier += 1.25;
			}
			else if ( CurLevel < 12 )
			{
				AdjustedModifier += 2.0;
			}
			else if ( CurLevel < 13 )
			{
				AdjustedModifier += 2.5;
			}
			else //if ( CurLevel > 12 )
			{
				AdjustedModifier += 3.0;
			}
		}
	}
	
	AdjustedModifier = AdjustedModifier / float(NumEnemies);
	AdjustedModifier = AdjustedModifier * PlayerCountHealthScale;

	return AdjustedModifier;
}

defaultproperties
{
	Health=12000
	HealthMax=12000
	PlayerCountHealthScale=0.4
	MenuName="Phantom of Kevin Clamelly"
	bBoss=False
	bHasBoss=False
}
