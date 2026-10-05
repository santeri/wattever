#include "joule_spi.h"

extern CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef group, CFStringRef subgroup, uint64_t a,
                                                    uint64_t b, uint64_t c);
extern IOReportSubscriptionRef IOReportCreateSubscription(void *allocator, CFMutableDictionaryRef desired,
                                                           CFMutableDictionaryRef *subscribed, uint64_t unit,
                                                           CFTypeRef options);
extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef subscription, CFMutableDictionaryRef channels,
                                              CFTypeRef options);
extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef previous, CFDictionaryRef current,
                                                   CFTypeRef options);
extern CFStringRef IOReportChannelGetChannelName(CFDictionaryRef channel);
extern CFStringRef IOReportChannelGetUnitLabel(CFDictionaryRef channel);
extern int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef channel, int32_t index);

static void copy_string(CFStringRef string, char *buffer, CFIndex capacity) {
  if (string == NULL || !CFStringGetCString(string, buffer, capacity, kCFStringEncodingUTF8)) {
    buffer[0] = '\0';
  }
}

CFDictionaryRef joule_copy_energy_channels(void) {
  CFDictionaryRef channels = IOReportCopyChannelsInGroup(CFSTR("Energy Model"), NULL, 0, 0, 0);
  if (channels == NULL) {
    return NULL;
  }
  CFMutableDictionaryRef mutable = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, channels);
  CFRelease(channels);
  return mutable;
}

IOReportSubscriptionRef joule_subscribe(CFDictionaryRef channels) {
  CFMutableDictionaryRef subscribed = NULL;
  IOReportSubscriptionRef subscription =
      IOReportCreateSubscription(NULL, (CFMutableDictionaryRef)channels, &subscribed, 0, NULL);
  if (subscribed != NULL) {
    CFRelease(subscribed);
  }
  return subscription;
}

void joule_release_subscription(IOReportSubscriptionRef subscription) {
  if (subscription != NULL) {
    CFRelease(subscription);
  }
}

CFDictionaryRef joule_copy_samples(IOReportSubscriptionRef subscription, CFDictionaryRef channels) {
  return IOReportCreateSamples(subscription, (CFMutableDictionaryRef)channels, NULL);
}

CFDictionaryRef joule_copy_delta(CFDictionaryRef previous, CFDictionaryRef current) {
  return IOReportCreateSamplesDelta(previous, current, NULL);
}

void joule_visit_channels(CFDictionaryRef sample, JouleVisit visit, void *context) {
  if (sample == NULL || visit == NULL) {
    return;
  }
  CFArrayRef items = CFDictionaryGetValue(sample, CFSTR("IOReportChannels"));
  if (items == NULL) {
    return;
  }
  CFIndex count = CFArrayGetCount(items);
  for (CFIndex index = 0; index < count; index++) {
    CFDictionaryRef channel = CFArrayGetValueAtIndex(items, index);
    char name[160];
    char unit[32];
    copy_string(IOReportChannelGetChannelName(channel), name, sizeof name);
    copy_string(IOReportChannelGetUnitLabel(channel), unit, sizeof unit);
    visit(name, unit, IOReportSimpleGetIntegerValue(channel, 0), context);
  }
}
