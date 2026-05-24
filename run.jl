#!/usr/bin/julia
using JuMP
using Clp

include("data.jl")
include("model.jl")

m, x = build_model(se)
set_optimizer(m, Clp.Optimizer)
optimmize!(m)
