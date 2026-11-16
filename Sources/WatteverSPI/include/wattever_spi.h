#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>

// Opaque IOReport subscription. Released with wattever_release_subscription.
typedef struct IOReportSubscription *IOReportSubscriptionRef;

typedef void (*WatteverVisit)(const char *_Nonnull name, const char *_Nonnull unit, int64_t raw,
                           void *_Nullable context);

// Energy Model channel dictionary. Caller owns the returned object.
CF_RETURNS_RETAINED
CFDictionaryRef _Nullable wattever_copy_energy_channels(void);

// `channels` must stay alive for as long as the subscription is used.
IOReportSubscriptionRef _Nullable wattever_subscribe(CFDictionaryRef _Nonnull channels);

void wattever_release_subscription(IOReportSubscriptionRef _Nullable subscription);

CF_RETURNS_RETAINED
CFDictionaryRef _Nullable wattever_copy_samples(IOReportSubscriptionRef _Nonnull subscription,
                                              CFDictionaryRef _Nonnull channels);

CF_RETURNS_RETAINED
CFDictionaryRef _Nullable wattever_copy_delta(CFDictionaryRef _Nonnull previous, CFDictionaryRef _Nonnull current);

// Invokes `visit` once per channel in an IOReport sample or delta.
void wattever_visit_channels(CFDictionaryRef _Nonnull sample, WatteverVisit _Nonnull visit, void *_Nullable context);

// Merged PMP channel dictionary (`PMP`, then `PMP0`..`PMP7`). Caller owns it.
// NULL when this machine publishes none.
CF_RETURNS_RETAINED
CFDictionaryRef _Nullable wattever_copy_pmp_channels(void);

typedef void (*WatteverStateVisit)(const char *_Nonnull name, const char *_Nonnull subgroup,
                                   const char *_Nonnull state, uint64_t residency, void *_Nullable context);

// Invokes `visit` once per state of each Energy-subgroup histogram in a sample or delta.
void wattever_visit_states(CFDictionaryRef _Nonnull sample, WatteverStateVisit _Nonnull visit,
                           void *_Nullable context);

// DRAM rail watts from SMC `PZD1` and the following per-die keys. Negative when unread.
double wattever_dram_watts(void);
