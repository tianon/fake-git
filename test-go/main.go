package main

import (
	"fmt"
	"runtime/debug"
)

func main() {
	bi, ok := debug.ReadBuildInfo()
	if !ok {
		panic("failed to read build info")
	}
	fmt.Println(bi.Main.Version)
	for _, setting := range bi.Settings {
		if len(setting.Key) >= 3 && setting.Key[:3] == "vcs" {
			fmt.Printf("%s = %q\n", setting.Key, setting.Value)
		}
	}
}
