# vendor_id="1af4"
# device_id="1000"
# PCI_IDS_PATH="/init-setup/resources/pci.ids"

# awk -v v_id="${vendor_id}" -v d_id="${device_id}" '
#         BEGIN { vendor_found = 0 }

#         # 1. Vendor Section 
#         # Line의 시작이 들여쓰기 없이 Vendor ID 이면서 첫 필드가 Vendor ID
#         $1 == v_id && $0 ~ ("^" v_id "[[:space:]]") {
#             vendor_name = substr($0, index($0, $2));
#             vendor_found = 1;
#             # print "Vendor ID : " v_id
#             # print "Vendor Name : " vendor_name; 
#             next;
#         }

#         # Device line (1 indented with tab)
#         vendor_found == 1 && d_id == $1 {
#             # print "DEBUG: Line:", NR, " | $1:", $1, " | $0:", $0
#             device_name = substr($0, index($0, $2));
#             print " Vendor Name : " vendor_name; 
#             print " Device_name : " device_name;
#             next;
#         }

#         # Next vendor starts, stop searching
#         vendor_found == 1 && $0 ~ /^[0-9a-fA-F]{4}[[:space:]]/ {
#             # print "Other Vendor section... Exit";
#             exit;
#         }        
#     ' "${PCI_IDS_PATH}"

# example() {
#     declare -A pci_map 
#     pci_map["vendor"]="Intel"
#     pci_map["device"]="82599ES"

#     # JSON 형태로 출력
#     printf '{"vendor":"%s","device":"%s"}\n' \
#         "${pci_map["vendor"]}" \
#         "${pci_map["device"]}"
# }

# json_result=$(example)
# vendor=$(echo "${json_result}" | jq -r '.vendor')
# device=$(echo "${json_result}" | jq -r '.device')

# echo "json_result : ${json_result}"
# echo "vendor : ${vendor}"
# echo "device : ${device}"

