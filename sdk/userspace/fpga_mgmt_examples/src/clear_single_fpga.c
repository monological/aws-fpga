/*
 * Copyright 2025 Amazon.com, Inc. or its affiliates. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"). You may
 * not use this file except in compliance with the License. A copy of the
 * License is located at
 *
 *     http://aws.amazon.com/apache2.0/
 *
 * or in the "license" file accompanying this file. This file is distributed
 * on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
 * express or implied. See the License for the specific language governing
 * permissions and limitations under the License.
 */

/*
 * This example demonstrates how to clear the image from a single FPGA image slot using the C API.
 * 0. Prerequisites: This example must be run on an F2 instance with an FPGA at FPGA image slot 0. Source the sdk by
 *    navigating to the root of this repo and running `source ./sdk_setup.sh`.
 * 1. fpga_mgmt_init: Initialize the fpga_mgmt library to allow use of the other API calls used in this example.
 * 2. fpga_mgmt_clear_local_image_sync: Clear the image from the fpga. This operation will clear the specified FPGA
 *    image slot including internal and external memories that are used by the slot.
 * 3. Display and Verify: Display and verify the contents returned in the fpga_mgmt_image_info struct.
 * 4. fpga_mgmt_close: Close the fpga_mgmt library at the end of the example.
 */

#include <stdio.h>
#include <fpga_mgmt.h>
#include <utils/log.h>
#include <unistd.h>
#include <string.h>

void display_image_info(struct fpga_mgmt_image_info *info);
int verify_image_info_cleared(struct fpga_mgmt_image_info *info);

int main(int argc, char ** argv) {
  (void)argc;
  (void)argv;

  int slot_id = 0;
  /* Number of internal calls to fpga_mgmt_describe_local_image attempted by the fpga_mgmt_clear_local_image_sync function. */
  uint32_t num_retries = 30000;
  /* Delay in milliseconds between internal calls to fpga_mgmt_describe_local_image by the fpga_mgmt_clear_local_image_sync function. */
  uint32_t retry_delay = 2;

  int ret = FPGA_ERR_FAIL;
  /* 1. fpga_mgmt_init: */
  ret = fpga_mgmt_init();
  fail_on(ret != 0, err, "fpga_mgmt_init failed. Running this example on a non-F2 instance or not sourcing the sdk can cause this call to fail.");

  /* fpga_mgmt_clear_local_image_sync: */
  printf("Clearing FPGA image slot %d\n", slot_id);
  struct fpga_mgmt_image_info info;
  ret = fpga_mgmt_clear_local_image_sync(slot_id, num_retries, retry_delay, &info);
  fail_on(ret != 0, err, "fpga_mgmt_clear_local_image_sync failed. An incorrect slot_id or a lower num_retries can cause the this call to fail.");

  /* 3. Display and Verify: */
  display_image_info(&info);
  ret = verify_image_info_cleared(&info);
  fail_on(ret != 0, err, "Image info verification failed");

err:
  /* 4. fpga_mgmt_close: */
  fpga_mgmt_close();
  return ret;
}

void display_image_info(struct fpga_mgmt_image_info *info) {
  printf("Contents of fpga_mgmt_image_info\n");
  printf("status: %s\n", FPGA_STATUS2STR(info->status));
  printf("status qualifier: %s\n", FPGA_ERR2STR(info->status_q));
  printf("slot id: %d\n", info->slot_id);
  printf("afi id: %s\n", info->ids.afi_id);
  struct fpga_pci_resource_map* app_map = &info->spec.map[FPGA_APP_PF];
  printf("Application PF domain:bus:dev.func: %04X:%02X:%02X.%X\n", app_map->domain, app_map->bus, app_map->dev, app_map->func);
  struct fpga_pci_resource_map* mgmt_map = &info->spec.map[FPGA_MGMT_PF];
  printf("Management PF domain:bus:dev.func: %04X:%02X:%02X.%X\n", mgmt_map->domain, mgmt_map->bus, mgmt_map->dev, mgmt_map->func);
  printf("Shell version: 0x%X\n", info->sh_version);
}

int verify_image_info_cleared(struct fpga_mgmt_image_info *info) {
  if (info->status != FPGA_STATUS_CLEARED) {
    printf("Image status is not cleared\n");
    return -1;
  }
  if (info->status_q != FPGA_ERR_OK) {
    printf("Image status qualifier is not ok\n");
    return -1;
  }
  if (info->spec.map[FPGA_APP_PF].device_id != 0x9048) {
    printf("Device ID is not the default/cleared id\n");
    return -1;
  }
  if (info->spec.map[FPGA_APP_PF].vendor_id != 0x1d0f) {
    printf("Vendor ID is not the default/cleared id\n");
    return -1;
  }
  if (strcmp(info->ids.afi_id, "No AFI")) {
    printf("AFI ID is not the default/cleared id\n");
    return -1;
  }
  return 0;
}