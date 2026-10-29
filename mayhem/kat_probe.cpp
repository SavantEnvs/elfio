// Known-answer probe for mayhem/test.sh: prints parsed fields of an ELF file for exact comparison.
#include <iostream>

#include <elfio/elfio.hpp>

using namespace ELFIO;

int main( int argc, char** argv )
{
    if ( argc < 2 ) {
        return 2;
    }
    elfio elf;
    if ( !elf.load( argv[1] ) ) {
        std::cout << "load failed" << std::endl;
        return 1;
    }
    std::cout << "class=" << (int)elf.get_class() << " machine=" << elf.get_machine()
              << " type=" << elf.get_type() << " entry=0x" << std::hex << elf.get_entry()
              << std::dec << " sections=" << elf.sections.size()
              << " segments=" << elf.segments.size() << std::endl;
    for ( const auto& sec : elf.sections ) {
        if ( sec->get_name() == ".text" ) {
            std::cout << ".text size=" << sec->get_size() << " addr=0x" << std::hex
                      << sec->get_address() << std::dec << std::endl;
        }
    }
    return 0;
}
