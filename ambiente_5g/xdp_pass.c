#include <linux/bpf.h>
#define SEC(NAME) __attribute__((section(NAME), used))

SEC("xdp")
int xdp_pass_func(struct xdp_md *ctx) {
    return XDP_PASS;
}

SEC("license")
char _license[] = "GPL";
