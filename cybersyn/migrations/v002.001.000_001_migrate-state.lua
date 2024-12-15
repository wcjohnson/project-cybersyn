game.print("Migrating Cybersyn: v002.001.000_001...")

-- Create missing global states
if not storage.combinators then storage.combinators = {} end
if not storage.combinator_uis then storage.combinator_uis = {} end
if not storage.train_stops then storage.train_stops = {} end

-- LORD: Close all open combinator GUIs for all players

-- LORD: Migrate combinators from legacy combinator caches: `to_comb`, `to_comb_params`, and `to_stop`

-- Destroy legacy combinator caches
storage.to_comb = nil
storage.to_comb_params = nil
storage.to_output = nil
storage.to_stop = nil
