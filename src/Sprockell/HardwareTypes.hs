{-# LANGUAGE FlexibleInstances, DeriveGeneric, DeriveAnyClass #-}
module Sprockell.HardwareTypes where

import GHC.Generics
import Control.DeepSeq
import qualified Data.Sequence as Sequence
import qualified Data.Array    as Array
import qualified Data.Foldable as Foldable

-- ==========================================================================================================
-- Types and sizes for: data, memory, communication channels
-- ==========================================================================================================
-- Constraints will possibly require conversions -- KEEP IT SIMPLE!
-- * MemAddr (for both local and shared memory) should fit in registers for indirect addressing
-- * Register content should be usable as code address
-- * Possibly that shared memory is bigger than local memory
-- * Etcetera ...
-- ==> Choice: avoid conversions, too complicated. So keep all these the same as much as possible.
-- ==========================================================================================================

type CodeAddr   = Int                                           -- * Instruction Address in Assembly Program (Program Counter)
type RegAddr    = Int                                           -- * Register Address
type MemAddr    = Int                                           -- * Local Memory Address (incl Stack Pointer)
type Label      = String

type Value      = Int
type SprID      = Value

data AddrImmDI  = ImmValue Int                                  -- ImmValue n:is just the constant value n
                | DirAddr MemAddr                               -- DirAddr a: a is an address in memory (local or shared)
                | IndAddr RegAddr                               -- IndAddr p: p is a register, the content of this register is an address inmemory
                deriving (Eq,Show,Read)

type LocalMem   = Sequence.Seq Value
type RegBank    = [Value]
type SharedMem  = Sequence.Seq Value

type InstructionMem = Array.Array Int Instruction

type Reply      = Maybe Value                                   -- Every clock cycle an input arrives from shared memory, probably most of the time Nothing
data Request    = NoRequest                                     -- No request to shared memory
                | ReadReq MemAddr                               -- Request to shared memory to send the value at the given address
                | WriteReq Value MemAddr                        -- Request to write a value to a given address in shared memory
                | TestReq MemAddr                               -- Request to test-and-Set at the given address in shared memory
                deriving (Eq,Show,Generic,NFData)

type IndRequests        = [(SprID, Request)]                    -- A list of requests together with the sprockell-IDs of the sender
type IndReplies         = [(SprID, Reply)]                      -- Ibid for replies

type RequestChannel     = [Request]
type RequestChannels    = [RequestChannel]
type ReplyChannel       = [Reply]
type ReplyChannels      = [ReplyChannel]

type ParRequests        = [Request]                             -- all requests sent by the Sprockells in parallel (at each clock cycle)
type ParReplies         = [Reply]                               -- ibid for replies
type RequestFifo        = [(SprID,Request)]                     -- Collects all Sprockell requests as input for Shared Memory


-- ==========================================================================================================
-- Memory type class + instances
-- ==========================================================================================================

class Memory m where
    fromList :: [a] -> m a
    toList   :: m a -> [a]
    (!)      :: m a -> Int -> a                      -- indexing
    (<~)     :: m a -> (Int,a) -> m a                -- mem <~ (i,x): put value x at address i in mem

    (<~!)    :: m a -> (Int,a) -> m a                -- ibid, but leave address 0 unchanged
    xs <~! (i,x)    | i == 0        = xs
                    | otherwise     = xs <~ (i,x)


instance Memory [] where
    fromList        = id
    toList          = id
    xs ! i          = xs !! i
    []     <~ _     = []                             -- silently ignore update after end of list
    (x:xs) <~ (0,y) = y:xs
    (x:xs) <~ (n,y) = x : (xs <~ (n-1,y))

instance Memory (Array.Array Int) where
    fromList xs = Array.listArray (0,length xs) xs
    toList      = Array.elems
    (!)         = (Array.!)
    xs <~ (i,x) = xs Array.// [(i,x)]

instance Memory Sequence.Seq where
    fromList    = Sequence.fromList
    toList      = Foldable.toList
    (!)         = Sequence.index
    xs <~ (i,x) = Sequence.update i x xs



-- ==========================================================================================================
-- Internal state for Sprockell and System
-- ==========================================================================================================
data SprockellState = SprState
        { pc            :: !CodeAddr                            -- Program counter
        , sp            :: !MemAddr                             -- Stack pointer
        , regbank       :: !RegBank                             -- Register bank
        , localMem      :: !LocalMem                            -- Local memory
        } deriving (Eq,Show)                                    --      Exclamation mark for eager (non-lazy) evaluation

data SystemState = SystemState
        { sprStates     :: ![SprockellState]                    -- list of all Sprockell states
        , requestChnls  :: ![RequestChannel]                    -- list of all request channels
        , replyChnls    :: ![ReplyChannel]                      -- list of all reply channels
        , requestFifo   :: !RequestFifo                         -- request fifo for buffering requests
        , sharedMem     :: !SharedMem                           -- shared memory
        } deriving (Eq,Show)                                    --      Exclamation mark for eager (non-lazy) evaluation

-- ==========================================================================================================
-- SprIL: Sprockell Instruction Language
-- ==========================================================================================================
data Operator    = Add   | Sub | Mul -- | Div | Mod             -- Computational operations -- No Div, Mod because of hardware complexity
                 | Equal | NEq | Gt  | Lt     | GtE | LtE       -- Comparison operations
                 | And   | Or  | Xor | LShift | RShift          -- Logical operations
                 | Decr  | Incr                                 -- Decrement (-1), Increment (+1)
                 deriving (Eq,Show,Read)

data Instruction = Compute Operator RegAddr RegAddr RegAddr     -- Compute op r0 r1 r2: go to "alu",
                                                                --      do "op" on regs r0, r1, and put result in reg r2
                 | Jump Target                                  -- Jump t: jump to target t (absolute, relative, indirect)
                 | Branch RegAddr Target                        -- Branch r t: conditional jump, depending on register r
                                                                --      if r contains 0: don't jump; otherwise: jump

                 | Load AddrImmDI RegAddr                       -- Load (ImmValue n) r: put value n in register r
                                                                -- Load (DirAddr a) r : put value on memory address a in r
                                                                -- Load (IndAddr p) r : ibid, but memory address is in register p

                 | Store RegAddr AddrImmDI                      -- Store r (DirAddr a): from register r to memory address a
                                                                -- Store r (IndAddr p): ibid, memory address contained in register p
                                                                -- Store r (ImmValue n): undefined

                 | Push RegAddr                                 -- Push r: put the value from register r on the stack
                 | Pop RegAddr                                  -- Pop r : put the top of the stack in register r
                                                                --         and adapts the stack pointer

                 | ReadInstr AddrImmDI                          -- ReadInstr a: Send read request for shMem address a
                 | Receive RegAddr                              -- Receive r  : Wait for reply and save it in register r
                 | WriteInstr RegAddr AddrImmDI                 -- WriteInstr r a: Write content of reg r to shMem address a
                 | TestAndSet AddrImmDI                         -- Request a test on address for 0 and sets it to 1 if it is.
                                                                -- Reply will contain 1 on success, and 0 on failure.
                                                                -- This is an atomic operation; it might therefore be
                                                                -- used to implement locks or synchronisation.

                                                                -- For ReadInstr, WriteInstr, TestAndSet:
                                                                --     address only as DirAddr, IndAddr; not as ImmValue

                 | EndProg                                      -- end of program, deactivates Sprockell. If all sprockells are at
                                                                -- this instruction, the simulation will halt.

                 | Nop                                          -- Operation "do nothing"
                 
                 | LabelInst Label

                 | Debug String                                 -- No real instruction, for debug purposes.
                 deriving (Eq,Show,Read)

-- ==========================================================================================================
-- Data structures for communication within and between Sprockells
-- ==========================================================================================================
data Target     = Abs CodeAddr                                  -- Abs n: instruction n
                | Rel CodeAddr                                  -- Rel n: increase current program counter with n
                | Ind RegAddr                                   -- Ind r: value of new program counter is in register r
                | Lab Label                
                deriving (Eq,Show,Read)

data TargetCode = NoJump                                        -- code to indicate in machine code how to jump
                | TAbs
                | TRel
                | TInd
                | Waiting
                deriving (Eq,Show)

data AguCode    = AguDir                                        -- code to tell agu how to calculate the address in memory
                | AguInd
                | AguPush
                | AguPop
                deriving (Eq,Show)

data LdCode     = LdImm                                         -- code that indicates which value to load in register
                | LdAlu
                | LdMem
                | LdInp
                deriving (Eq,Show)

data StCode     = StNone                                        -- code to tell which value to put in memory
                | StMem
                deriving (Eq,Show)

data SPCode     = Down                                          -- code that tells how the stack pointer should be changed
                | Flat
                | Up
                deriving (Eq,Show)

data IOCode     = IONone                                        -- code to instruct IO-functions
                | IORead
                | IOWrite
                | IOTest
                deriving (Eq,Show)

data MachCode = MachCode                                        -- machine code: fields contain codes as described above
        { ldCode        :: LdCode
        , stCode        :: StCode
        , aguCode       :: AguCode
        , branch        :: Bool
        , tgtCode       :: TargetCode
        , spCode        :: SPCode
        , aluCode       :: Operator
        , ioCode        :: IOCode
        , immValue      :: Value
        , regX          :: RegAddr                              -- selects first register
        , regY          :: RegAddr                              -- selects second register
        , loadReg       :: RegAddr                              -- register to load a value to
        , addrImm       :: MemAddr                              -- address for memory
        } deriving (Eq,Show)




-- ==========================================================================================================
-- Clock for simulation
-- ==========================================================================================================
data Tick  = Tick        deriving (Eq,Show)
type Clock = [Tick]
clock = repeat Tick


-- ==========================================================================================================
-- These instances are used by the deepseq in Simulation.systemSim to avoid space-leaks
-- ==========================================================================================================
instance NFData SprockellState where
    rnf (SprState pc sp regbank localMem)
        = rnf pc
          `seq` rnf sp
          `seq` localMem  -- specificly only evaluate localMem to WHNF, Sequence should be strict already
          `seq` rnf regbank

instance NFData SystemState where
    rnf (SystemState sprStates requestChnls replyChnls requestFifo sharedMem)
        = rnf sprStates
          `seq` rnf requestChnls
          `seq` rnf replyChnls
          `seq` rnf requestFifo
          `seq` sharedMem  -- specificly only evaluate sharedMem to WHNF, Sequence should be strict already
          `seq` ()
