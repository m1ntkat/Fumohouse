local CameraController = require("CameraController")

local MotionState = {
    CharacterState = {
        NONE = 0,
        IDLE = 1,
        JUMPING = 2,
        FALLING = 4,
        WALKING = 8,
        CLIMBING = 16,
    },
}

MotionState.__index = MotionState

export type WallInfo = {
    point: Vector3,
    normal: Vector3,
    collider: Object,
}

---------------------
-- MotionProcessor --
---------------------

local MotionProcessor = { ID = "" }
MotionProcessor.__index = MotionProcessor

function MotionProcessor.Initialize(self: MotionProcessor, state: MotionState)
end

function MotionProcessor.HandleCancel(self: MotionProcessor, state: MotionState)
end

function MotionProcessor.Process(self: MotionProcessor, state: MotionState, delta: number)
end

function MotionProcessor.GetVelocity(self: MotionProcessor): Vector3?
    return nil
end

export type MotionProcessor = {
    ID: string,

    Initialize: (self: MotionProcessor, state: MotionState) -> (),
    HandleCancel: (self: MotionProcessor, state: MotionState) -> (),
    Process: (self: MotionProcessor, state: MotionState, delta: number) -> (),
    GetVelocity: (self: MotionProcessor) -> Vector3?,
}

MotionState.MotionProcessor = MotionProcessor

-------------------
-- MotionContext --
-------------------

local MotionContext = {}
MotionContext.__index = MotionContext

function MotionContext.new()
    local self = {}

    -- Input
    self.inputDirection = Vector3.ZERO
    self.camBasisFlat = Basis.IDENTITY

    -- State

    -- List of motion processor IDs which should be cancelled.
    -- Order of processing matters.
    self.cancelledProcessors = {} :: {[string]: boolean}

    -- States which don't really make sense to be applied
    -- (i.e. WALKING when CLIMBING)
    self.cancelledStates = 0

    -- Output
    self.newState = MotionState.CharacterState.NONE
    self.offset = Vector3.ZERO
    self.newBasis = Basis.IDENTITY

    return setmetatable(self, MotionContext)
end

function MotionContext.Reset(self: MotionContext)
    table.clear(self.cancelledProcessors)
    self.cancelledStates = 0
    self.newState = 0
    self.offset = Vector3.ZERO
end

function MotionContext.SetState(self: MotionContext, state: number)
    self.newState = bit32.bor(self.newState, state)
end

function MotionContext.CancelProcessor(self: MotionContext, id: string)
    self.cancelledProcessors[id] = true
end

function MotionContext.CancelState(self: MotionContext, state: number)
    self.cancelledStates = bit32.bor(self.cancelledStates, state)
end

export type MotionContext = typeof(MotionContext.new())

-----------------
-- MotionState --
-----------------

function MotionState.new()
    local self = {}

    -- Managed externally --

    -- Objects
    self.node = (nil :: any) :: Node -- Kinda janky but avoids unnecessary asserts
    self.rid = RID.new()
    self.camera = nil :: CameraController.CameraController?

    self.mainCollider = (nil :: any) :: CollisionShape3D
    self.mainCollisionShape = (nil :: any) :: CapsuleShape3D

    -- Callbacks
    self.GetTransform = function() return Transform3D.IDENTITY end
    self.SetTransform = function(transform: Transform3D) end
    self.GetWorld3D = (function() return assert(nil) end) :: () -> World3D
    self.MoveAndCollide = (function() return nil end) :: (motion: Vector3, margin: number) -> KinematicCollision3D?

    -- Options
    self.options = {
        maxGroundAngle = 45,
        margin = 0.001,
    }

    -- State
    self.walls = {} :: {WallInfo}
    self.velocity = Vector3.ZERO

    -- Managed locally --

    -- State
    self.state = MotionState.CharacterState.IDLE

    self.isGrounded = false
    self.groundRid = RID.new()
    self.groundNormal = Vector3.ZERO
    self.groundOverride = {} :: {[string]: Vector3}

    -- Processors
    self.ctx = MotionContext.new()
    self.motionProcessors = {} :: {MotionProcessor}

    local function addProcessor(file: string)
        table.insert(
            self.motionProcessors,
            (require(`processors/{file}.mod`) :: any).new()
        )
    end

    addProcessor("LadderMotion")
    addProcessor("HorizontalMotion")
    addProcessor("PhysicalMotion")
    addProcessor("StairsMotion")
    addProcessor("PlatformMotion")

    addProcessor("Move")
    addProcessor("Grounding")
    addProcessor("Walls")

    addProcessor("AreaHandler")
    addProcessor("CharacterAnimator")

    return setmetatable(self, MotionState)
end

function MotionState.ShouldPush(rid: RID): boolean
    local mode = PhysicsServer3D.GetSingleton():BodyGetMode(rid)
    return mode == PhysicsServer3D.BodyMode.RIGID or mode == PhysicsServer3D.BodyMode.RIGID_LINEAR
end

function MotionState.Initialize(self: MotionState, config)
    self.node = config.node
    self.rid = config.rid

    self.mainCollider = config.mainCollider
    self.mainCollisionShape = config.mainCollisionShape

    self.GetTransform = config.GetTransform
    self.SetTransform = config.SetTransform
    self.GetWorld3D = config.GetWorld3D
    self.MoveAndCollide = config.MoveAndCollide

    self:SetBodyMode(PhysicsServer3D.BodyMode.KINEMATIC)

    for _, processor in self.motionProcessors do
        processor:Initialize(self)
    end
end

function MotionState.IsStableGround(self: MotionState, normal: Vector3): boolean
    local ANGLE_MARGIN = 0.01
    return normal:AngleTo(Vector3.UP) <= math.rad(self.options.maxGroundAngle) + ANGLE_MARGIN
end

function MotionState.TestMotion(self: MotionState, params: PhysicsTestMotionParameters3D, result: PhysicsTestMotionResult3D?): boolean
    return PhysicsServer3D.GetSingleton():BodyTestMotion(self.rid, params, result)
end

function MotionState.SetBodyMode(self: MotionState, mode: ClassEnumPhysicsServer3D_BodyMode)
    PhysicsServer3D.GetSingleton():BodySetMode(self.rid, mode)
end

function MotionState.GetMotionProcessor(self: MotionState, id: string): any
    for _, motion in self.motionProcessors do
        if motion.ID == id then
            return motion
        end
    end

    return nil
end

function MotionState.IsState(self: MotionState, state: number): boolean
    return bit32.band(self.state, state) ~= 0
end

function MotionState.Update(self: MotionState, delta: number)
    assert(self.camera)

    local origTransform = self.GetTransform()

    -- Update context
    self.ctx:Reset()

    local inputDirection2 = Input.GetSingleton():GetVector("move_left", "move_right", "move_forward", "move_backward")
    self.ctx.inputDirection = Vector3.new(inputDirection2.x, 0, inputDirection2.y)
    self.ctx.camBasisFlat = Basis.IDENTITY:Rotated(Vector3.UP, self.camera.cameraRotation.y)
    self.ctx.newBasis = origTransform.basis

    -- Process
    -- Every step of movement from finding the ground to actually moving the character is covered by these processors.
    for _, processor in self.motionProcessors do
        if self.ctx.cancelledProcessors[processor.ID] then
            processor:HandleCancel(self)
        else
            processor:Process(self, delta)
        end
    end

    -- Update state
    if self.ctx.newState == MotionState.CharacterState.NONE then
        self.state = MotionState.CharacterState.IDLE
    else
        self.state = bit32.band(
            self.ctx.newState,
            bit32.bnot(self.ctx.cancelledStates)
        )
    end
end

export type MotionState = typeof(MotionState.new())
return MotionState