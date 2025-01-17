local DebugDrawImpl = {}
local DebugDraw = gdclass(nil, MeshInstance3D)
    :RegisterImpl(DebugDrawImpl)

type LineInfo = {
    timeAlive: number,
    lifetime: number,
    p1: Vector3,
    p2: Vector3,
    c1: Color,
    c2: Color,
}

export type DebugDraw = MeshInstance3D & typeof(DebugDrawImpl) & {
    mesh: ImmediateMesh,

    lines: {LineInfo},
}

function DebugDrawImpl._Init(self: DebugDraw)
    self.mesh = ImmediateMesh.new()
    self.lines = {}

    local mat = StandardMaterial3D.new()
    mat.noDepthTest = true
    mat.shadingMode = BaseMaterial3D.ShadingMode.UNSHADED
    mat.vertexColorUseAsAlbedo = true
    self.materialOverride = mat

    -- Should process after everything
    self.processPriority = 500
end

function DebugDrawImpl.DrawLine(self: DebugDraw, p1: Vector3, p2: Vector3, c1: Color, c2: Variant, lifetime: number?)
    local c2A = if c2 == nil then c1 else c2 :: Color

    self.lines[#self.lines + 1] = {
        timeAlive = 0,
        lifetime = lifetime or 0,
        p1 = p1,
        p2 = p2,
        c1 = c1,
        c2 = c2A
    }
end

DebugDraw:RegisterMethodAST("DrawLine")
    :DefaultArgs(nil, 0)

function DebugDrawImpl.DrawMarker(self: DebugDraw, pos: Vector3, color: Color, lifetime: number?, size: number?)
    local sizeA = size or 0.05

    local camera = assert(self:GetViewport():GetCamera3D())

    local camBasis = camera.globalTransform.basis
    local camX = camBasis.x
    local camY = camBasis.y

    self:DrawLine(
        pos + (camX + camY) * sizeA,
        pos + (-camX - camY) * sizeA,
        color,
        nil,
        lifetime
    )

    self:DrawLine(
        pos + (-camX + camY) * sizeA,
        pos + (camX - camY) * sizeA,
        color,
        nil,
        lifetime
    )
end

DebugDraw:RegisterMethodAST("DrawMarker")
    :DefaultArgs(0, 0.05)

function DebugDrawImpl._Process(self: DebugDraw, delta: number)
    self.mesh:ClearSurfaces()

    if #self.lines == 0 then
        return
    end

    self.mesh:SurfaceBegin(Mesh.PrimitiveType.LINES)

    for i = #self.lines, 1, -1 do
        local lineInfo = self.lines[i]

        lineInfo.timeAlive += delta
        if lineInfo.timeAlive >= lineInfo.lifetime then
            table.remove(self.lines, i)
        end

        self.mesh:SurfaceSetColor(lineInfo.c1)
        self.mesh:SurfaceAddVertex(lineInfo.p1)
        self.mesh:SurfaceSetColor(lineInfo.c2)
        self.mesh:SurfaceAddVertex(lineInfo.p2)
    end

    self.mesh:SurfaceEnd()
end

DebugDraw:RegisterMethodAST("_Process")

return DebugDraw
