#include "wattever_spi.h"

#include <IOKit/IOKitLib.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

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
extern CFStringRef IOReportChannelGetSubGroup(CFDictionaryRef channel);
extern CFStringRef IOReportChannelGetUnitLabel(CFDictionaryRef channel);
extern int IOReportStateGetCount(CFDictionaryRef channel);
extern CFStringRef IOReportStateGetNameForIndex(CFDictionaryRef channel, int index);
extern uint64_t IOReportStateGetResidency(CFDictionaryRef channel, int index);
extern int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef channel, int32_t index);

static void copy_string(CFStringRef string, char *buffer, CFIndex capacity) {
  if (string == NULL || !CFStringGetCString(string, buffer, capacity, kCFStringEncodingUTF8)) {
    buffer[0] = '\0';
  }
}

CFDictionaryRef wattever_copy_energy_channels(void) {
  CFDictionaryRef channels = IOReportCopyChannelsInGroup(CFSTR("Energy Model"), NULL, 0, 0, 0);
  if (channels == NULL) {
    return NULL;
  }
  CFMutableDictionaryRef mutable = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, channels);
  CFRelease(channels);
  return mutable;
}

IOReportSubscriptionRef wattever_subscribe(CFDictionaryRef channels) {
  CFMutableDictionaryRef subscribed = NULL;
  IOReportSubscriptionRef subscription =
      IOReportCreateSubscription(NULL, (CFMutableDictionaryRef)channels, &subscribed, 0, NULL);
  if (subscribed != NULL) {
    CFRelease(subscribed);
  }
  return subscription;
}

void wattever_release_subscription(IOReportSubscriptionRef subscription) {
  if (subscription != NULL) {
    CFRelease(subscription);
  }
}

CFDictionaryRef wattever_copy_samples(IOReportSubscriptionRef subscription, CFDictionaryRef channels) {
  return IOReportCreateSamples(subscription, (CFMutableDictionaryRef)channels, NULL);
}

CFDictionaryRef wattever_copy_delta(CFDictionaryRef previous, CFDictionaryRef current) {
  return IOReportCreateSamplesDelta(previous, current, NULL);
}

void wattever_visit_channels(CFDictionaryRef sample, WatteverVisit visit, void *context) {
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

static CFMutableDictionaryRef copy_named_group(const char *name) {
  CFStringRef group = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingUTF8);
  CFDictionaryRef channels = IOReportCopyChannelsInGroup(group, NULL, 0, 0, 0);
  CFRelease(group);
  if (channels == NULL) {
    return NULL;
  }
  CFArrayRef items = CFDictionaryGetValue(channels, CFSTR("IOReportChannels"));
  if (items == NULL || CFArrayGetCount(items) == 0) {
    CFRelease(channels);
    return NULL;
  }
  CFMutableDictionaryRef mutable = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, channels);
  CFRelease(channels);
  return mutable;
}

CFDictionaryRef wattever_copy_pmp_channels(void) {
  const char *names[] = {"PMP", "PMP0", "PMP1", "PMP2", "PMP3", "PMP4", "PMP5", "PMP6", "PMP7"};
  CFMutableDictionaryRef merged = NULL;
  for (size_t index = 0; index < sizeof names / sizeof names[0]; index++) {
    CFMutableDictionaryRef group = copy_named_group(names[index]);
    if (group == NULL) {
      continue;
    }
    if (merged == NULL) {
      merged = group;
      continue;
    }
    CFArrayRef extra = CFDictionaryGetValue(group, CFSTR("IOReportChannels"));
    CFMutableArrayRef items =
        CFArrayCreateMutableCopy(kCFAllocatorDefault, 0, CFDictionaryGetValue(merged, CFSTR("IOReportChannels")));
    CFArrayAppendArray(items, extra, CFRangeMake(0, CFArrayGetCount(extra)));
    CFDictionarySetValue(merged, CFSTR("IOReportChannels"), items);
    CFRelease(items);
    CFRelease(group);
  }
  return merged;
}

void wattever_visit_states(CFDictionaryRef sample, WatteverStateVisit visit, void *context) {
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
    CFStringRef subgroup = IOReportChannelGetSubGroup(channel);
    if (subgroup == NULL || CFStringCompare(subgroup, CFSTR("Energy"), 0) != kCFCompareEqualTo) {
      continue;
    }
    CFDataRef raw = CFDictionaryGetValue(channel, CFSTR("RawElements"));
    if (raw == NULL || CFGetTypeID(raw) != CFDataGetTypeID() || CFDataGetLength(raw) < 17) {
      continue;
    }
    // kIOReportFormatState. Simple channels crash the state calls.
    if (CFDataGetBytePtr(raw)[16] != 2) {
      continue;
    }
    int states = IOReportStateGetCount(channel);
    if (states <= 0 || states > 64) {
      continue;
    }
    char name[160];
    char group[80];
    copy_string(IOReportChannelGetChannelName(channel), name, sizeof name);
    copy_string(subgroup, group, sizeof group);
    for (int state = 0; state < states; state++) {
      char label[64];
      copy_string(IOReportStateGetNameForIndex(channel, state), label, sizeof label);
      visit(name, group, label, IOReportStateGetResidency(channel, state), context);
    }
  }
}

typedef struct {
  char major;
  char minor;
  char build;
  char reserved;
  uint16_t release;
} SMCVers;

typedef struct {
  uint16_t version;
  uint16_t length;
  uint32_t cpuPLimit;
  uint32_t gpuPLimit;
  uint32_t memPLimit;
} SMCPLimit;

typedef struct {
  uint32_t dataSize;
  uint32_t dataType;
  uint8_t dataAttributes;
} SMCKeyInfo;

typedef struct {
  uint32_t key;
  SMCVers vers;
  SMCPLimit pLimitData;
  SMCKeyInfo keyInfo;
  uint8_t result;
  uint8_t status;
  uint8_t data8;
  uint32_t data32;
  uint8_t bytes[32];
} SMCKeyData;

static io_connect_t smc_connection(void) {
  static io_connect_t connection = 0;
  static int tried = 0;
  if (tried) {
    return connection;
  }
  tried = 1;
  io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
  if (service == 0) {
    return 0;
  }
  if (IOServiceOpen(service, mach_task_self(), 0, &connection) != KERN_SUCCESS) {
    connection = 0;
  }
  IOObjectRelease(service);
  return connection;
}

static uint32_t smc_fourcc(const char *name) {
  return ((uint32_t)name[0] << 24) | ((uint32_t)name[1] << 16) | ((uint32_t)name[2] << 8) | (uint32_t)name[3];
}

static int smc_read_float(io_connect_t connection, const char *name, float *value) {
  SMCKeyData input;
  SMCKeyData output;
  memset(&input, 0, sizeof input);
  input.key = smc_fourcc(name);
  input.data8 = 9;
  size_t inputSize = sizeof input;
  size_t outputSize = sizeof output;
  if (IOConnectCallStructMethod(connection, 2, &input, inputSize, &output, &outputSize) != KERN_SUCCESS ||
      output.result != 0) {
    return 0;
  }
  uint32_t type = output.keyInfo.dataType;
  uint32_t size = output.keyInfo.dataSize;
  char typeName[4] = {(char)(type >> 24), (char)(type >> 16), (char)(type >> 8), (char)type};
  if (size < 4 || memcmp(typeName, "flt ", 4) != 0) {
    return 0;
  }
  memset(&input, 0, sizeof input);
  input.key = smc_fourcc(name);
  input.keyInfo.dataSize = size;
  input.data8 = 5;
  inputSize = sizeof input;
  outputSize = sizeof output;
  if (IOConnectCallStructMethod(connection, 2, &input, inputSize, &output, &outputSize) != KERN_SUCCESS ||
      output.result != 0) {
    return 0;
  }
  uint32_t bits = (uint32_t)output.bytes[0] | ((uint32_t)output.bytes[1] << 8) | ((uint32_t)output.bytes[2] << 16) |
                  ((uint32_t)output.bytes[3] << 24);
  memcpy(value, &bits, sizeof *value);
  return 1;
}

double wattever_dram_watts(void) {
  io_connect_t connection = smc_connection();
  if (connection == 0) {
    return -1;
  }
  static int keyCount = -1;
  if (keyCount < 0) {
    keyCount = 0;
    for (int index = 1; index <= 8; index++) {
      char name[5];
      float value = 0;
      snprintf(name, sizeof name, "PZD%d", index);
      if (!smc_read_float(connection, name, &value)) {
        break;
      }
      keyCount = index;
    }
  }
  if (keyCount == 0) {
    return -1;
  }
  double sum = 0;
  int saw = 0;
  for (int index = 1; index <= keyCount; index++) {
    char name[5];
    float value = 0;
    snprintf(name, sizeof name, "PZD%d", index);
    if (!smc_read_float(connection, name, &value) || !isfinite(value) || value <= 0 || value > 80) {
      continue;
    }
    sum += value;
    saw = 1;
  }
  return saw ? sum : -1;
}
