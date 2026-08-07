import 'package:anime_chat_app/grounding_contract.dart';

GroundingAcceptancePolicy groundingAuditPolicyFor(int index) {
  return switch (index) {
    1 => const GroundingAcceptancePolicy(
        minimumFacts: 3,
        maximumSearchApiCalls: 1,
        requiredFactText: ['寺内清', '中原澄', '高田奈穗'],
      ),
    2 => const GroundingAcceptancePolicy(
        minimumFacts: 5,
        requireTimeline: true,
        maximumSearchApiCalls: 1,
        requiredSearchObjects: ['时透无一郎'],
      ),
    3 => const GroundingAcceptancePolicy(
        minimumFacts: 5,
        requireTimeline: true,
        maximumSearchApiCalls: 0,
        requiredSearchObjects: ['蝴蝶忍'],
      ),
    4 => const GroundingAcceptancePolicy(
        minimumFacts: 2,
        maximumSearchApiCalls: 0,
        requiredSearchObjects: ['蝴蝶忍'],
        requiredFactText: ['金鱼'],
      ),
    5 => const GroundingAcceptancePolicy(
        minimumFacts: 5,
        requireTimeline: true,
        maximumSearchApiCalls: 0,
      ),
    6 => const GroundingAcceptancePolicy(
        minimumFacts: 2,
        maximumSearchApiCalls: 0,
        requiredSearchObjects: ['时透无一郎'],
      ),
    7 => const GroundingAcceptancePolicy(
        minimumFacts: 2,
        maximumSearchApiCalls: 0,
        requiredSearchObjects: ['高松灯'],
        requiredFactText: ['企鹅', '天文馆'],
      ),
    8 => const GroundingAcceptancePolicy(
        minimumFacts: 5,
        requireTimeline: true,
        maximumSearchApiCalls: 0,
        requiredSearchObjects: ['椎名立希'],
      ),
    9 => const GroundingAcceptancePolicy(
        minimumFacts: 6,
        requireTimeline: true,
        maximumSearchApiCalls: 2,
        requiredSearchObjects: ['千早爱音', '高松灯'],
        requiredFactText: ['水族馆', '天台'],
        orderedTimelineAnchors: ['水族馆', '全班', '回到乐队'],
      ),
    10 => const GroundingAcceptancePolicy(
        minimumFacts: 1,
        maximumSearchApiCalls: 3,
        requiredSearchObjects: ['KiLLKiSS'],
      ),
    11 => const GroundingAcceptancePolicy(
        minimumFacts: 1,
        maximumSearchApiCalls: 2,
      ),
    12 => const GroundingAcceptancePolicy(
        minimumFacts: 0,
        maximumSearchApiCalls: 0,
      ),
    13 => const GroundingAcceptancePolicy(
        minimumFacts: 1,
        maximumSearchApiCalls: 2,
      ),
    _ => const GroundingAcceptancePolicy(),
  };
}
