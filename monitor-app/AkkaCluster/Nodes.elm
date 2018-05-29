module AkkaCluster.Nodes exposing
  ( Nodes
  , empty
  , NodeUrl
  , insertClusterMembers
  , removeClusterMembers
  , nodeHostname
  , sourceNodes
  , sourceHostname
  , sortedAllNodes
  , nodeInfo
  , NodeStatus (..)
  )

import Dict exposing (Dict)
import AkkaCluster.Json exposing (ClusterMember, ClusterMembers, MemberStatus, NodeAddress, decodeMembers)
import Maybe exposing (withDefault)
import Regex exposing (HowMany(AtMost), regex, split)
import Set exposing (Set)
import AkkaCluster.Json

type alias Nodes = Dict NodeUrl ClusterNode

type alias ClusterNode = { selfNode: NodeAddress
                         , knownNodes: Dict NodeAddress NodeInfo
                         }

empty : Nodes
empty = Dict.empty

type alias NodeUrl = String

type NodeStatus = NodeStatus AkkaCluster.Json.MemberStatus
                | UnknownNodeStatus

type alias NodeInfo =
  { status : NodeStatus
  , isLeader : Bool
  , isOldest : Bool
  }

insertClusterMembers : Nodes -> NodeUrl -> ClusterMembers -> Nodes
insertClusterMembers nodes nodeUrl clusterMembers =
  Dict.insert nodeUrl (clusterMembersToClusterNode clusterMembers) nodes

removeClusterMembers : Nodes -> NodeUrl -> Nodes
removeClusterMembers nodes nodeUrl = Dict.remove nodeUrl nodes


nodeHostname : NodeAddress -> String
nodeHostname node = withDefault node <| List.head <| List.drop 2 <| split (AtMost 3) (regex "[@:]") node

sourceNodes : Nodes -> List NodeUrl
sourceNodes nodes = List.sortBy (sourceHostname nodes) (Dict.keys nodes)

sortedAllNodes : Nodes -> List NodeAddress
sortedAllNodes nodes = List.sort <| List.map .selfNode (Dict.values nodes)

maybeMemberStatus : NodeAddress -> ClusterMembers -> Maybe String
maybeMemberStatus node cm = List.head <| List.map (\m -> toString m.status)
                                      <| List.filter (\m -> m.node == node) cm.members

sourceHostname : Nodes -> NodeUrl -> String
sourceHostname nodes source = withDefault source <| Maybe.map nodeHostname (sourceNode nodes source)

nodeInfo : Nodes -> NodeUrl -> NodeAddress -> Maybe NodeInfo
nodeInfo nodes source node = nodes |> Dict.get source
                                   |> Maybe.map .knownNodes
                                   |> Maybe.andThen (Dict.get node)

------------------------------------------------------------------------------------------------------------------------

sourceNode : Nodes -> NodeUrl -> Maybe NodeAddress
sourceNode nodes source = Maybe.map (.selfNode) (Dict.get source nodes)

clusterMembersToClusterNode : ClusterMembers -> ClusterNode
clusterMembersToClusterNode cm =
  let
    knownNodeAddresses : List NodeAddress
    knownNodeAddresses = List.map .node cm.members

    knownNodes : Dict NodeAddress NodeInfo
    knownNodes = Dict.fromList <| List.map (\node -> (node, nodeInfoFromClusterMembers node cm)) knownNodeAddresses
  in
    { selfNode = cm.selfNode
    , knownNodes = knownNodes
    }

nodeInfoFromClusterMembers : NodeAddress -> ClusterMembers -> NodeInfo
nodeInfoFromClusterMembers node members =
  let
    isUnreachable : Bool
    isUnreachable = List.any (\u -> u.node == node && List.member members.selfNode u.observedBy) members.unreachable

    nodeStatus : Maybe MemberStatus
    nodeStatus = List.head <| List.map (.status) <| List.filter (\m -> m.node == node) members.members
  in
    { status = if isUnreachable
               then UnknownNodeStatus
               else withDefault UnknownNodeStatus <| Maybe.map NodeStatus nodeStatus
    , isLeader = members.leader == node
    , isOldest = members.oldest == node
    }


