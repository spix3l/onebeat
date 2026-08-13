#pragma once

#include <string>

namespace onebeat::plugin::sandbox {

int runRuntimeHost(const std::string& bundle_path, const std::string& plugin_id,
                   const std::string& shared_memory_name);

}  // namespace onebeat::plugin::sandbox
