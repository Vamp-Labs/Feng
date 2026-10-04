// TEMPORARY — ABI sketch transcribed from docs/handoffs/05-social-registry.md (Plan 2, SocialRegistry).
// Delete this file and switch src/lib/social-registry.ts to import socialRegistryAbi from
// "@/lib/abi/generated" once that generated module lands.
export const socialRegistrySketchAbi = [
  {
    type: "function",
    name: "follow",
    stateMutability: "nonpayable",
    inputs: [{ name: "target", type: "address" }],
    outputs: [],
  },
  {
    type: "function",
    name: "unfollow",
    stateMutability: "nonpayable",
    inputs: [{ name: "target", type: "address" }],
    outputs: [],
  },
  {
    type: "function",
    name: "followerCount",
    stateMutability: "view",
    inputs: [{ name: "target", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "isFollowing",
    stateMutability: "view",
    inputs: [
      { name: "user", type: "address" },
      { name: "target", type: "address" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "followedBy",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "targets", type: "address[]" }],
  },
  {
    type: "function",
    name: "setProfile",
    stateMutability: "nonpayable",
    inputs: [
      { name: "handle", type: "string" },
      { name: "bio", type: "string" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "profileOf",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [
      { name: "handle", type: "string" },
      { name: "bio", type: "string" },
    ],
  },
  {
    type: "function",
    name: "ownerOfHandle",
    stateMutability: "view",
    inputs: [{ name: "handle", type: "string" }],
    outputs: [{ name: "owner", type: "address" }],
  },
  {
    type: "event",
    name: "Followed",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "target", type: "address", indexed: true },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "Unfollowed",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "target", type: "address", indexed: true },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "ProfileSet",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "handle", type: "string", indexed: false },
      { name: "bio", type: "string", indexed: false },
    ],
    anonymous: false,
  },
  { type: "error", name: "ZeroAddress", inputs: [] },
  { type: "error", name: "CannotFollowSelf", inputs: [] },
  { type: "error", name: "AlreadyFollowing", inputs: [] },
  { type: "error", name: "NotFollowing", inputs: [] },
  { type: "error", name: "InvalidHandleLength", inputs: [] },
  { type: "error", name: "InvalidHandleChar", inputs: [] },
  { type: "error", name: "HandleTaken", inputs: [] },
  { type: "error", name: "BioTooLong", inputs: [] },
] as const;
