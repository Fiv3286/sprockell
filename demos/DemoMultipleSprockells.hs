module DemoMultipleSprockells where

import Sprockell

-- prog :: [Instruction]
-- prog = [
--            Branch regSprID (Rel 6)     -- target "beginLoop"
--          , Load (ImmValue 13) regC
--          , WriteInstr regC (DirAddr 1) -- Sprockell 1 must jump to second EndProg
--          , WriteInstr regC (DirAddr 2) -- Sprockell 2 must jump to second EndProg
--          , WriteInstr regC (DirAddr 3) -- Sprockell 3 must jump to second EndProg
--          , Jump (Abs 12)               -- Sprockell 0 jumps to first EndProg
--          -- beginLoop
--          , ReadInstr (IndAddr regSprID)
--          , Receive regA
--          , Compute Equal regA reg0 regB
--          , Branch regB (Rel (-3))
--          -- endLoop
--          , WriteInstr regA numberIO
--          , Jump (Ind regA)

--          -- 12: Sprockell 0 is sent here
--          , EndProg

--          -- 13: Sprockells 1, 2 and 3 are sent here
--          , EndProg
--        ]

--  lock test ; slow but works. 
-- prog :: [Instruction]
prog = [
      Load (ImmValue 0) regA, -- clear register A just in case
      -- loop start 
      TestAndSet (DirAddr 1),    -- try lock, reply will take at least 8 cycles
      Receive regA,           -- wait on lock attempt result
      Branch regA (Rel 2),    -- jump out of loop on sucessfull lock 
      Jump (Rel (-3)),         -- re-try lock on failure.   
      -- begin critial section
      ReadInstr (DirAddr 2),
      Receive regB,
      Compute Add regSprID regB regB,
      WriteInstr regB (DirAddr 2),
      -- end critial section

      WriteInstr reg0 (DirAddr 1), -- release lock
      EndProg
      ]

-- prog = [
--       TestAndSet (IndAddr regSprID),
--       Receive regA,
--       WriteInstr regA numberIO,
--       EndProg]
      

-- If you want to inspect the output, use debuggerSimplePrintAndWait
main = runWithDebugger (debuggerSimplePrint myShow) [prog,prog,prog,prog]

