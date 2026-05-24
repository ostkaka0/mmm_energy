import pyomo.environ as pyo
from pyomo.opt import SolverFactory

opt = SolverFactory('glpk')

model = pyo.ConcreteModel()
model.n = pyo.Param(default=4)
model.x = pyo.Var(pyo.RangeSet(model.n), within=pyo.Binary)

def o_rule(model):
  return pyo.summation(model.x)

model.o = pyo.Objective(rule=o_rule)
model.c = pyo.ConstraintList()

results = opt.solve(model)

if pyo.value(model.x[2]) == 0:
  print('2nd')
else:
  print(model.x[2])
