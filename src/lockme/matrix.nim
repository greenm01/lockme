import std/[random, times]

const
  MatrixMinStreamLength* = 3
  MatrixFrameStepMs* = 160
  MatrixGlyphs*: seq[string] = @[
    "Α", "Β", "Γ", "Δ", "Ε", "Ζ", "Η", "Θ", "Ι", "Κ", "Λ", "Μ", "Ν", "Ξ", "Ο", "Π", "Ρ", "Σ", "Τ",
    "Υ", "Φ", "Χ", "Ψ", "Ω", "+", "#", "%", "*"
  ]

type
  MatrixColumn* = object
    gapRemaining*: int
    length*: int
    updateEvery*: int
    phase*: int
    headRow*: int
    tailRow*: int
    glyphs*: seq[int] # Indices into MatrixGlyphs

  MatrixRain* = object
    width*: int
    height*: int
    tick*: uint64
    columns*: seq[MatrixColumn]
    rng*: Rand

  MatrixTicker* = object
    armed*: bool
    nextAtMs*: int64

proc matrixFrameTimeoutMs*(ticker: var MatrixTicker; visible: bool; nowMs: int64; frameMs: int): int =
    if not visible:
        ticker.armed = false
        return -1
    if not ticker.armed:
        ticker.armed = true
        ticker.nextAtMs = nowMs
    let remaining = ticker.nextAtMs - nowMs
    if remaining <= 0:
        0
    elif remaining > int64(high(cint)):
        high(cint)
    else:
        int(remaining)

proc matrixFrameDue*(ticker: var MatrixTicker; visible: bool; nowMs: int64; frameMs: int): bool =
    if not visible:
        ticker.armed = false
        return false
    if not ticker.armed:
        ticker.armed = true
        ticker.nextAtMs = nowMs
    if ticker.nextAtMs > nowMs:
        return false
    ticker.nextAtMs = nowMs + int64(max(frameMs, 1))
    true

proc makeColumn*(rain: var MatrixRain, height: int, columnIdx: int): MatrixColumn =
    if height <= 0:
        return MatrixColumn(
            gapRemaining: 0,
            length: 0,
            updateEvery: 1,
            phase: 0,
            headRow: -1,
            tailRow: 0,
            glyphs: @[]
        )
    let lengthMax = max(MatrixMinStreamLength, height - 3)
    let length = MatrixMinStreamLength + rain.rng.rand(lengthMax - MatrixMinStreamLength)
    result = MatrixColumn(
        gapRemaining: 1 + rain.rng.rand(height - 1),
        length: length,
        updateEvery: 1 + rain.rng.rand(2),
        phase: (columnIdx * 3 + rain.rng.rand(6)) mod 3,
        headRow: -1,
        tailRow: 0,
        glyphs: newSeq[int](height)
    )

proc advanceColumn(rain: var MatrixRain, columnIdx: int) =
    if rain.height == 0: return
    let height = rain.height
    
    if rain.columns[columnIdx].gapRemaining > 0:
        rain.columns[columnIdx].gapRemaining -= 1
        return
        
    if rain.columns[columnIdx].headRow < 0:
        let gIdx = rain.rng.rand(MatrixGlyphs.len - 1)
        rain.columns[columnIdx].headRow = 0
        rain.columns[columnIdx].tailRow = 0
        rain.columns[columnIdx].glyphs[0] = gIdx
        return

    rain.columns[columnIdx].headRow += 1
    let headRow = rain.columns[columnIdx].headRow
    
    if headRow < height:
        let gIdx = rain.rng.rand(MatrixGlyphs.len - 1)
        rain.columns[columnIdx].glyphs[headRow] = gIdx

    if headRow - rain.columns[columnIdx].tailRow + 1 > rain.columns[columnIdx].length:
        rain.columns[columnIdx].tailRow += 1

    let head = min(headRow, height - 1)
    let tail = max(0, rain.columns[columnIdx].tailRow)
    for row in tail ..< head:
        if rain.rng.rand(7) == 0:
            rain.columns[columnIdx].glyphs[row] = rain.rng.rand(MatrixGlyphs.len - 1)

    if rain.columns[columnIdx].tailRow >= height:
        rain.columns[columnIdx] = rain.makeColumn(height, columnIdx)

proc advance*(rain: var MatrixRain) =
    rain.tick = rain.tick + 1
    for i in 0 ..< rain.columns.len:
        if i mod 2 == 1: continue
        let updateEvery = rain.columns[i].updateEvery
        let phase = rain.columns[i].phase
        if (int(rain.tick) + phase) mod updateEvery != 0:
            continue
        rain.advanceColumn(i)

proc initMatrixRain*(width, height: int): MatrixRain =
    result = MatrixRain(
        width: width,
        height: height,
        tick: 0,
        rng: initRand(now().toTime().toUnix() xor (width.int64 shl 32 or height.int64))
    )
    result.columns = newSeq[MatrixColumn](width)
    for i in 0 ..< width:
        result.columns[i] = result.makeColumn(height, i)
    
    let warmupSteps = max(1, height + MatrixMinStreamLength + 2)
    for _ in 0 ..< warmupSteps:
        result.advance()
