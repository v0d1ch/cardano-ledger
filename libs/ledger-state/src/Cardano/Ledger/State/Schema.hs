{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-name-shadowing #-}

module Cardano.Ledger.State.Schema where

import Cardano.Ledger.Babbage.TxOut (BabbageTxOut)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Coin
import Cardano.Ledger.Conway.Governance
import Cardano.Ledger.Core (PParams)
import qualified Cardano.Ledger.Credential as Credential
import qualified Cardano.Ledger.Keys as Keys
import qualified Cardano.Ledger.PoolParams as Shelley
import qualified Cardano.Ledger.Shelley.LedgerState as Shelley
import qualified Cardano.Ledger.Shelley.PoolRank as Shelley
import Cardano.Ledger.State.Orphans (Enc, SnapShotType (..))
import Cardano.Ledger.State.UTxO
import qualified Cardano.Ledger.TxIn as TxIn
import qualified Data.Map.Strict as Map
import Database.Persist.Sqlite
import Database.Persist.TH

type FGenDelegs = (Enc (Map.Map Shelley.FutureGenDeleg Keys.GenDelegPair))

type CredentialWitness = Credential.Credential 'Keys.Witness

type KeyHashWitness = Keys.KeyHash 'Keys.Witness

share
  [mkPersist sqlSettings, mkMigrate "migrateAll"]
  [persistLowerCase|
EpochState
  treasury Coin
  reserves Coin
  prevPp (PParams CurrentEra)
  pp (PParams CurrentEra)
  nonMyopic Shelley.NonMyopic
  snapShotsFee Coin

SnapShot
  type SnapShotType
  epochStateId EpochStateId
  -- UniqueSnapShot type epochStateId
SnapShotStake
  snapShotId SnapShotId
  credentialId CredentialId
  coin (CompactForm Coin)
  UniqueSnapShotStake snapShotId credentialId
SnapShotDelegation
  snapShotId SnapShotId
  credentialId CredentialId
  keyHash KeyHashId
  UniqueSnapShotDelegation snapShotId credentialId
SnapShotPool
  snapShotId SnapShotId
  keyHashId KeyHashId
  params Shelley.PoolParams
  UniqueSnapShotPool snapShotId keyHashId

LedgerState
  utxoId UtxoStateId
  dstateId DStateId
  epochStateId EpochStateId
  pstateBin (Shelley.PState CurrentEra)
  UniqueLedgerStateUtxoId utxoId
  UniqueLedgerStateDStateId dstateId
  UniqueLedgerStateEpochStateId epochStateId
UtxoState
  deposited Coin
  fees Coin
  govState (ConwayGovState CurrentEra)
  donation Coin
DState
  fGenDelegs FGenDelegs
  genDelegs Keys.GenDelegs
  irDeltaReserves DeltaCoin
  irDeltaTreasury DeltaCoin

Credential
  witness CredentialWitness
  UniqueCredential witness
KeyHash
  witness KeyHashWitness
  UniqueKeyHash witness
Tx
  inIx TxIx
  inId TxIn.TxId
  out (BabbageTxOut CurrentEra)
  UniqueTx inIx inId
Txs
  inIx TxIx
  inId TxIn.TxId
  out (BabbageTxOut CurrentEra)
  stakeCredential CredentialId Maybe
  UniqueTxs inIx inId
UtxoEntry
  txId TxId
  txsId TxsId
  stateId UtxoStateId
Reward
  dstateId DStateId
  credentialId CredentialId
  coin Coin
  UniqueReward dstateId credentialId coin
Delegation
  dstateId DStateId
  credentialId CredentialId
  stakePoolId KeyHashId
  UniqueDelegation dstateId credentialId
DRep
  dstateId DStateId
  credentialId CredentialId
  dRepCredentialId CredentialId
  UniqueDRep dstateId credentialId
Ptr
  dstateId DStateId
  credentialId CredentialId
  ptr Credential.Ptr
  UniquePtrPtr dstateId ptr
  UniquePtrCredential dstateId credentialId
IRReserves
  dstateId DStateId
  credentialId CredentialId
  coin Coin
  UniqueIRReserves dstateId credentialId
IRTreasury
  dstateId DStateId
  credentialId CredentialId
  coin Coin
  UniqueIRTreasury dstateId credentialId
|]
