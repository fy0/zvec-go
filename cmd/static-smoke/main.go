package main

import (
	"fmt"
	"log"

	zvec "github.com/zvec-ai/zvec-go"
)

func main() {
	fmt.Printf("zvec version: %s\n", zvec.GetVersion())

	if err := zvec.Initialize(nil); err != nil {
		log.Fatalf("initialize zvec: %v", err)
	}
	if err := zvec.Shutdown(); err != nil {
		log.Fatalf("shutdown zvec: %v", err)
	}
}
