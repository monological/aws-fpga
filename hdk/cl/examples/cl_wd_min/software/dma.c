#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>
#include <stdarg.h>
#include <sys/mman.h>
#include <immintrin.h>

uint64_t _wd_get_phys(void* p)
{
    uint64_t PAGE_SIZE = (uint64_t)sysconf(_SC_PAGESIZE);
    int pagemap_fd;
    uint64_t vaddr;
    uintptr_t vpn;
    uint64_t pfn;

    pagemap_fd = open("/proc/self/pagemap", O_RDONLY);
    if (pagemap_fd < 0)
    {
        printf (( "cannot open pagemap file: %d ", pagemap_fd ));
        return 0;
    }

    vaddr = (uint64_t)p;
    vpn = vaddr / PAGE_SIZE;
    for (size_t nread = 0; nread < sizeof(pfn); )
    {
        ssize_t ret = pread(pagemap_fd, &pfn, sizeof(pfn) - nread, (off_t)((vpn * sizeof(pfn)) + nread));
        if (ret <= 0)
        {
            printf (( "pread error: %lu ", ret ));
            close(pagemap_fd);
            return 0;
        }
        nread += (size_t)ret;
    }
    pfn &= (1UL << 55) - 1;
    pfn = (pfn * (long unsigned int)PAGE_SIZE) + (vaddr % (long unsigned int)PAGE_SIZE);

    close(pagemap_fd);

    return pfn;
}

int main()
{
    uint32_t* mem = mmap(0, 32, PROT_READ|PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_LOCKED, -1, 0);
    uint64_t mem_p = _wd_get_phys(mem);
    printf ("%p\n", mem_p);

    for (int i = 0; i < 32; i ++)
    {
        mem[i] = 0x0;
    }

    while (1)
    {
        for (int i = 0; i < 32; i ++)
        {
            uint32_t w = mem[i];
            if (w)
                printf ("[%02d] = %08x\n", i, w);
        }
        sleep(1);
    }

    return 0;
}
