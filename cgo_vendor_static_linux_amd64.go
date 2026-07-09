//go:build !source && vendor_static && linux && amd64

package zvec

// Static vendor mode (Linux amd64): link against the pre-built static vendor
// archive in lib/linux_amd64_static. This is opt-in and does not affect the
// default dynamic vendor mode.
//
// Usage:
//
//	CGO_ENABLED=1 go build -tags vendor_static \
//	  -ldflags="-linkmode external -extldflags '-static -static-libstdc++ -static-libgcc'"

/*
#cgo CFLAGS: -I${SRCDIR}/lib/include
#cgo LDFLAGS: -L${SRCDIR}/lib/linux_amd64_static -Wl,--start-group -lzvec_c_api_static -Wl,--end-group -lstdc++ -lm -ldl -lpthread -lrt
*/
import "C"
