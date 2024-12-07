-- Migrate combinator settings cached in `storage` to the format required
-- by the new combinator API.

game.print("Running combinator API migration...")

if not storage.combinators then storage.combinators = {} end
if not storage.open_combinators then storage.open_combinators = {} end
if not storage.train_stops then storage.train_stops = {} end

-- TODO: close all open combinator guis

-- TODO: move combinator settings into storage.combinators

-- TODO: generate `Cybersyn.TrainStop`s from `Depot`, `Station`, `Refueler`
