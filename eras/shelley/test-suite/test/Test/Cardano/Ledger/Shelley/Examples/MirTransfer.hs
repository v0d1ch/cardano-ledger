{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

module Test.Cardano.Ledger.Shelley.Examples.MirTransfer (
  testMIRTransfer,
)
where

import Cardano.Ledger.BaseTypes (Mismatch (..), ProtVer (..), natVersion)
import Cardano.Ledger.Coin (Coin (..), DeltaCoin (..))
import Cardano.Ledger.Keys (
  GenDelegs (..),
  KeyRole (..),
  hashKey,
 )
import Cardano.Ledger.Shelley (ShelleyEra)
import Cardano.Ledger.Shelley.API (
  AccountState (..),
  Credential (..),
  DState (..),
  DelegEnv (..),
  InstantaneousRewards (..),
  Ptr (..),
  ShelleyDELEG,
 )
import Cardano.Ledger.Shelley.Core
import Cardano.Ledger.Shelley.Rules (ShelleyDelegPredFailure (..))
import Cardano.Ledger.Slot (SlotNo (..))
import qualified Cardano.Ledger.UMap as UM
import Control.State.Transition.Extended hiding (Assertion)
import Data.List.NonEmpty (NonEmpty)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Lens.Micro
import Test.Cardano.Ledger.Shelley.ConcreteCryptoTypes (C_Crypto)
import Test.Cardano.Ledger.Shelley.Utils (RawSeed (..), applySTSTest, mkKeyPair, runShelleyBase)
import Test.Control.State.Transition.Trace (checkTrace, (.-), (.->>))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, testCase, (@?=))

type ShelleyTest = ShelleyEra C_Crypto

ignoreAllButIRWD ::
  Either (NonEmpty (PredicateFailure (ShelleyDELEG ShelleyTest))) (DState ShelleyTest) ->
  Either (NonEmpty (PredicateFailure (ShelleyDELEG ShelleyTest))) (InstantaneousRewards C_Crypto)
ignoreAllButIRWD = fmap dsIRewards

env :: ProtVer -> AccountState -> DelegEnv ShelleyTest
env pv acnt =
  DelegEnv
    { slotNo = SlotNo 50
    , ptr_ = Ptr (SlotNo 50) minBound minBound
    , acnt_ = acnt
    , ppDE = emptyPParams & ppProtocolVersionL .~ pv
    }

shelleyPV :: ProtVer
shelleyPV = ProtVer (natVersion @2) 0

alonzoPV :: ProtVer
alonzoPV = ProtVer (natVersion @5) 0

testMirTransfer ::
  ProtVer ->
  MIRPot ->
  MIRTarget C_Crypto ->
  InstantaneousRewards C_Crypto ->
  AccountState ->
  Either (NonEmpty (PredicateFailure (ShelleyDELEG ShelleyTest))) (InstantaneousRewards C_Crypto) ->
  Assertion
testMirTransfer pv pot target ir acnt (Right expected) = do
  checkTrace @(ShelleyDELEG ShelleyTest) runShelleyBase (env pv acnt) $
    (pure (dStateWithRewards ir)) .- (MirTxCert (MIRCert pot target)) .->> (dStateWithRewards expected)
testMirTransfer pv pot target ir acnt predicateFailure@(Left _) = do
  let st =
        runShelleyBase $
          applySTSTest @(ShelleyDELEG ShelleyTest)
            (TRC (env pv acnt, dStateWithRewards ir, MirTxCert (MIRCert pot target)))
  (ignoreAllButIRWD st) @?= predicateFailure

dStateWithRewards :: InstantaneousRewards c -> DState (ShelleyEra c)
dStateWithRewards ir =
  DState
    { dsUnified = UM.empty
    , dsFutureGenDelegs = Map.empty
    , dsGenDelegs = GenDelegs Map.empty
    , dsIRewards = ir
    }

alice :: Credential 'Staking C_Crypto
alice = (KeyHashObj . hashKey . snd) $ mkKeyPair (RawSeed 0 0 0 0 1)

aliceOnlyReward :: Integer -> Map (Credential 'Staking C_Crypto) Coin
aliceOnlyReward c = Map.fromList [(alice, Coin c)]

aliceOnlyDelta :: Integer -> Map (Credential 'Staking C_Crypto) DeltaCoin
aliceOnlyDelta c = Map.fromList [(alice, DeltaCoin c)]

bob :: Credential 'Staking C_Crypto
bob = (KeyHashObj . hashKey . snd) $ mkKeyPair (RawSeed 0 0 0 0 2)

bobOnlyReward :: Integer -> Map (Credential 'Staking C_Crypto) Coin
bobOnlyReward c = Map.fromList [(bob, Coin c)]

bobOnlyDelta :: Integer -> Map (Credential 'Staking C_Crypto) DeltaCoin
bobOnlyDelta c = Map.fromList [(bob, DeltaCoin c)]

testMIRTransfer :: TestTree
testMIRTransfer =
  testGroup
    "MIR cert transfers"
    [ testGroup
        "MIR cert embargos"
        [ testCase "embargo reserves to treasury transfer" $
            testMirTransfer
              shelleyPV
              ReservesMIR
              (SendToOppositePotMIR $ Coin 1)
              (InstantaneousRewards mempty mempty mempty mempty)
              (AccountState {asReserves = Coin 1, asTreasury = Coin 0})
              (Left . pure $ MIRTransferNotCurrentlyAllowed)
        , testCase "embargo treasury to reserves transfer" $
            testMirTransfer
              shelleyPV
              TreasuryMIR
              (SendToOppositePotMIR $ Coin 1)
              (InstantaneousRewards mempty mempty mempty mempty)
              (AccountState {asReserves = Coin 0, asTreasury = Coin 1})
              (Left . pure $ MIRTransferNotCurrentlyAllowed)
        , testCase "embargo decrements from reserves" $
            testMirTransfer
              shelleyPV
              ReservesMIR
              (StakeAddressesMIR $ aliceOnlyDelta (-1))
              (InstantaneousRewards (aliceOnlyReward 1) mempty mempty mempty)
              (AccountState {asReserves = Coin 1, asTreasury = Coin 0})
              (Left . pure $ MIRNegativesNotCurrentlyAllowed)
        , testCase "embargo decrements from treasury" $
            testMirTransfer
              shelleyPV
              TreasuryMIR
              (StakeAddressesMIR $ aliceOnlyDelta (-1))
              (InstantaneousRewards mempty (aliceOnlyReward 1) mempty mempty)
              (AccountState {asReserves = Coin 0, asTreasury = Coin 1})
              (Left . pure $ MIRNegativesNotCurrentlyAllowed)
        ]
    , testGroup
        "MIR cert alonzo"
        [ testCase "increment reserves too much" $
            testMirTransfer
              alonzoPV
              ReservesMIR
              (StakeAddressesMIR $ aliceOnlyDelta 1)
              (InstantaneousRewards (aliceOnlyReward 1) mempty mempty mempty)
              (AccountState {asReserves = Coin 1, asTreasury = Coin 0})
              (Left . pure $ InsufficientForInstantaneousRewardsDELEG ReservesMIR $ Mismatch (Coin 2) (Coin 1))
        , testCase "increment treasury too much" $
            testMirTransfer
              alonzoPV
              TreasuryMIR
              (StakeAddressesMIR $ aliceOnlyDelta 1)
              (InstantaneousRewards mempty (aliceOnlyReward 1) mempty mempty)
              (AccountState {asReserves = Coin 0, asTreasury = Coin 1})
              (Left . pure $ InsufficientForInstantaneousRewardsDELEG TreasuryMIR $ Mismatch (Coin 2) (Coin 1))
        , testCase "increment reserves too much with delta" $
            testMirTransfer
              alonzoPV
              ReservesMIR
              (StakeAddressesMIR $ aliceOnlyDelta 1)
              (InstantaneousRewards (aliceOnlyReward 1) mempty (DeltaCoin (-1)) (DeltaCoin 1))
              (AccountState {asReserves = Coin 2, asTreasury = Coin 0})
              (Left . pure $ InsufficientForInstantaneousRewardsDELEG ReservesMIR $ Mismatch (Coin 2) (Coin 1))
        , testCase "increment treasury too much with delta" $
            testMirTransfer
              alonzoPV
              TreasuryMIR
              (StakeAddressesMIR $ aliceOnlyDelta 1)
              (InstantaneousRewards mempty (aliceOnlyReward 1) (DeltaCoin 1) (DeltaCoin (-1)))
              (AccountState {asReserves = Coin 0, asTreasury = Coin 2})
              (Left . pure $ InsufficientForInstantaneousRewardsDELEG TreasuryMIR $ Mismatch (Coin 2) (Coin 1))
        , testCase "negative balance in reserves mapping" $
            testMirTransfer
              alonzoPV
              ReservesMIR
              (StakeAddressesMIR $ aliceOnlyDelta (-1))
              (InstantaneousRewards mempty mempty mempty mempty)
              (AccountState {asReserves = Coin 1, asTreasury = Coin 0})
              (Left . pure $ MIRProducesNegativeUpdate)
        , testCase "negative balance in treasury mapping" $
            testMirTransfer
              alonzoPV
              TreasuryMIR
              (StakeAddressesMIR $ aliceOnlyDelta (-1))
              (InstantaneousRewards mempty mempty mempty mempty)
              (AccountState {asReserves = Coin 0, asTreasury = Coin 1})
              (Left . pure $ MIRProducesNegativeUpdate)
        , testCase "transfer reserves to treasury" $
            testMirTransfer
              alonzoPV
              ReservesMIR
              (SendToOppositePotMIR (Coin 1))
              (InstantaneousRewards mempty mempty mempty mempty)
              (AccountState {asReserves = Coin 1, asTreasury = Coin 0})
              (Right (InstantaneousRewards mempty mempty (DeltaCoin (-1)) (DeltaCoin 1)))
        , testCase "transfer treasury to reserves" $
            testMirTransfer
              alonzoPV
              TreasuryMIR
              (SendToOppositePotMIR (Coin 1))
              (InstantaneousRewards mempty mempty mempty mempty)
              (AccountState {asReserves = Coin 0, asTreasury = Coin 1})
              (Right (InstantaneousRewards mempty mempty (DeltaCoin 1) (DeltaCoin (-1))))
        , testCase "insufficient transfer reserves to treasury" $
            testMirTransfer
              alonzoPV
              ReservesMIR
              (SendToOppositePotMIR (Coin 1))
              (InstantaneousRewards (aliceOnlyReward 1) mempty (DeltaCoin (-1)) (DeltaCoin 1))
              (AccountState {asReserves = Coin 2, asTreasury = Coin 0})
              (Left . pure $ InsufficientForTransferDELEG ReservesMIR $ Mismatch (Coin 1) (Coin 0))
        , testCase "insufficient transfer treasury to reserves" $
            testMirTransfer
              alonzoPV
              TreasuryMIR
              (SendToOppositePotMIR (Coin 1))
              (InstantaneousRewards mempty (aliceOnlyReward 1) (DeltaCoin 1) (DeltaCoin (-1)))
              (AccountState {asReserves = Coin 0, asTreasury = Coin 2})
              (Left . pure $ InsufficientForTransferDELEG TreasuryMIR $ Mismatch (Coin 1) (Coin 0))
        , testCase "increment reserves mapping" $
            testMirTransfer
              alonzoPV
              ReservesMIR
              (StakeAddressesMIR $ (aliceOnlyDelta 1 `Map.union` bobOnlyDelta 1))
              (InstantaneousRewards (aliceOnlyReward 1) mempty mempty mempty)
              (AccountState {asReserves = Coin 3, asTreasury = Coin 0})
              ( Right
                  ( InstantaneousRewards
                      (aliceOnlyReward 2 `Map.union` bobOnlyReward 1)
                      mempty
                      mempty
                      mempty
                  )
              )
        , testCase "increment treasury mapping" $
            testMirTransfer
              alonzoPV
              TreasuryMIR
              (StakeAddressesMIR $ (aliceOnlyDelta 1 `Map.union` bobOnlyDelta 1))
              (InstantaneousRewards mempty (aliceOnlyReward 1) mempty mempty)
              (AccountState {asReserves = Coin 0, asTreasury = Coin 3})
              ( Right
                  ( InstantaneousRewards
                      mempty
                      (aliceOnlyReward 2 `Map.union` bobOnlyReward 1)
                      mempty
                      mempty
                  )
              )
        ]
    ]
