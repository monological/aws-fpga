#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>
#include <stdarg.h>
#include <sys/mman.h>
#include <immintrin.h>
#include <stdlib.h>

uint64_t _wd_get_phys(void* p)
{
    uint64_t PAGE_SIZE = (uint64_t)sysconf(_SC_PAGESIZE);
    int pagemap_fd = open("/proc/self/pagemap", O_RDONLY);
    if (pagemap_fd < 0)
    {
        printf("cannot open pagemap file: %d\n", pagemap_fd);
        return 0;
    }

    uint64_t vaddr = (uint64_t)p;
    uint64_t vpn = vaddr / PAGE_SIZE;
    uint64_t entry;

    if (pread(pagemap_fd, &entry, sizeof(entry), vpn * sizeof(entry)) != sizeof(entry))
    {
        perror("pread error");
        close(pagemap_fd);
        return 0;
    }

    close(pagemap_fd);

    // Check if page is present
    if (!(entry & (1ULL << 63)))
    {
        printf("Page not present in memory.\n");
        return 0;
    }

    uint64_t pfn = entry & ((1ULL << 55) - 1);
    return (pfn * PAGE_SIZE) + (vaddr % PAGE_SIZE);
}

int main()
{
    const size_t MAP_SIZE = 32 * sizeof(uint32_t);
    uint32_t* mem = mmap(NULL, MAP_SIZE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_LOCKED, -1, 0);
    if (mem == MAP_FAILED) {
        perror("mmap failed");
        return 1;
    }

    uint64_t mem_p = _wd_get_phys(mem);
    printf("Physical address: 0x%lx\n", mem_p);

    for (int i = 0; i < 32; i++)
    {
        mem[i] = 0x0;
    }

    while (1)
    {
        for (int i = 0; i < 32; i++)
        {
            uint32_t w = mem[i];
            if (w)
                printf("[%02d] = %08x\n", i, w);
        }
        sleep(1);
    }

    return 0;
}
