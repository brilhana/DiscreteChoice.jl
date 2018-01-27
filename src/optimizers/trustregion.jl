immutable trustregion{T<:Real}
    η1::T
    η2::T
    γ1::T
    γ2::T
end

function trdefaults()
    return trustregion(0.01, 0.9, 0.5, 0.5)
end

type trstate
    iter::Int64
    x::Vector
    xcand::Vector
    g::Vector
    step::Vector
    Δ::Float64
    ρ::Float64
    δ::Float64

    function trstate()
        state = new()
        state.δ = 1e-6
        return state
    end
end

function acceptcandidate!(state::trstate, b::trustregion)
    if state.ρ >= b.η1
        return true
    else
        return false
    end
end

function updateradius!(state::trstate, b::trustregion)
    if state.ρ >= b.η2
        stepnorm = norm(state.step)
        state.Δ = min(1e20, max(4 * stepnorm, state.Δ))
    elseif state.ρ >= b.η1
        state.Δ *= b.γ2
    else
        state.Δ *= b.γ1
    end
end

function cg(A::Matrix, b::Vector, x0::Vector, δ::Float64 = 1e-6)
    n = length(x0)
    x = x0
    g = b + A * x
    d = -g
    k = 0
    δ *= δ
    while dot(g, g) > δ
        Ad = A * d
        normd = dot(d, Ad)
        α = -dot(d, g) / normd
        x += α * d
        g = b + A *x
        γ = dot(g, Ad) / normd
        d = -g + γ * d
        k += 1
    end
    normd = dot(d, A * d)
    α = -dot(d, g) / normd
    x += α * d
    return x
end

function truncatedcg(g::Vector, H::Matrix, Δ::Float64)
    n::Int64 = length(g)
    s = zeros(n)
    normg0 = norm(g)
    v = g
    d = -v
    gv = dot(g, v)
    norm2d = gv
    norm2s = 0
    sMd = 0
    k::Int64 = 0
    Δ *= Δ
    while !stopcg(norm(g), normg0, k, n)
        Hd = H*d
        κ = dot(d, Hd)
        if κ <= 0
            σ = (-sMd + sqrt(sMd * sMd + norm2d * (Δ - dot(s, s)))) / norm2d
            s += σ*d
            break
        end
        α = gv/κ
        norm2s += α * (2 * sMd + α * norm2d)
        if norm2s >= Δ
            σ = (-sMd + sqrt(sMd * sMd + norm2d * (Δ - dot(s, s)))) / norm2d
            s += σ*d
            break
        end
        s += α * d
        g += α * Hd
        v = g
        newgv = dot(g, v)
        β = newgv / gv
        gv = newgv
        d = -v + β * d
        sMd = β * (sMd + α * norm2d)
        norm2d = gv + β * β * norm2d
        k += 1
    end
    return s
end

function stopcg(normg::Float64, normg0::Float64, k::Int64, kmax::Int64)
    χ::Float64 = 0.1
    θ::Float64 = 0.5
    if k == kmax || normg <= normg0 * min(χ, normg0 ^ θ)
        return true
    else
        return false
    end
end

function tr(f::Function, g!::Function, H!::Function,
            step::Function, x0::Vector, state::trstate = trstate(), maxiter::Int64 = 500, approxh::Bool = false)
    b = trdefaults()
    state.iter = 0
    state.x = x0
    n::Int64 = length(x0)
    δ = state.δ * state.δ
    state.g = zeros(n)
    H = eye(n, n)
    fx = f(x0)
    g!(x0, state.g)
    state.Δ = 0.1 * norm(state.g)
    if approxh
        y = zeros(n)
        gcand = zeros(n)
    else
        H!(x0, H)
    end

    function model(s::Vector, g::Vector, H::Matrix)
        return dot(s, g) + 0.5 * dot(s, H * s)
    end

    while dot(state.g, state.g) > δ && state.iter < maxiter
        #if truncatedcg
        state.step = step(state.g, H, state.Δ)
        #elseif cg
        #state.step = step(H, state.g, x0)
        state.xcand = state.x + state.step
        fcand = f(state.xcand)
        state.ρ = (fcand - fx) / (model(state.step, state.g, H))
        if approxh
            g!(state.xcand, gcand)
            y = gcand - state.g
            H = H!(H, y, state.step)
        end
        if acceptcandidate!(state, b)
            state.x = copy(state.xcand)
            if !approxh
                g!(state.x, state.g)
                H!(state.x, H)
            else
                state.g = copy(gcand)
            end
            fx = fcand
        end
        updateradius!(state, b)
        state.iter += 1
    end
    return state.x
end