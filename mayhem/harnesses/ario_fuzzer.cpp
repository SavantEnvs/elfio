// Fuzzes ARIO, ELFIO's UNIX ar archive reader: parse the archive, then read every member.
#include <cstdint>
#include <memory>
#include <sstream>
#include <string>

#include <ario/ario.hpp>

using namespace ARIO;

extern "C" int LLVMFuzzerTestOneInput( const std::uint8_t* Data, size_t Size )
{
    std::string str( (const char*)Data, Size );
    ario        archive;

    auto result = archive.load( std::make_unique<std::istringstream>( str ) );
    if ( !result.ok() ) {
        return -1;
    }

    size_t total = 0;
    for ( const auto& member : archive.members ) {
        total += member.name.size() + member.data().size();
    }
    volatile size_t sink = total;
    (void)sink;

    return 0;
}
