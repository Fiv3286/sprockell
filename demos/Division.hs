module Division where

import Sprockell
import Data.Char




prog = [ Load (ImmValue 849892) regA,
        Load (ImmValue 5) regB,
        Load (ImmValue 1) regE , -- 1 to incr stuff
        -- regA / regB
        Load (ImmValue 0) regC ,
        -- begin division loop
        Load (ImmValue 0) regD ,
        Compute Lt regA regB regD, -- if A less than B, we finished. 
        Branch regD (Rel 4),         -- branch to remainder fixer; 
        Compute Sub regA regB regA, -- if not, subtract B from A once.
        Compute Add regE regC regC, -- increment
        Jump (Rel (-5)),
        Push regA,
        Pop regB,
        Nop
    ] ++ writeString "result" ++ [
        WriteInstr regC numberIO
    ] ++ writeString "remainder" ++ [
        WriteInstr regB numberIO,
        EndProg
    ]

main_1 = runWithDebugger (debuggerSimplePrint myShow') [prog]
main = run [prog]

writeString :: String -> [Instruction]
writeString str = concat $ map writeChar str

writeChar :: Char -> [Instruction]
writeChar c =
    [ Load (ImmValue $ ord c) regA
    , WriteInstr regA charIO
    ]