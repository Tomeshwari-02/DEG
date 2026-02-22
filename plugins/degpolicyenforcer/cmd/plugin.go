// Package main provides the plugin entry point for the DEG Policy Enforcer plugin.
// This file is compiled as a Go plugin (.so) and loaded by beckn-onix at runtime.
package main

import (
	"context"

	"github.com/beckn-one/beckn-onix/pkg/plugin/definition"
	degpolicyenforcer "github.com/beckn-one/deg/plugins/degpolicyenforcer"
)

// provider implements the StepProvider interface for plugin loading.
type provider struct{}

// New creates a new DEGPolicyEnforcer step instance.
func (p provider) New(ctx context.Context, cfg map[string]string) (definition.Step, func(), error) {
	enforcer, err := degpolicyenforcer.New(cfg)
	if err != nil {
		return nil, nil, err
	}

	return enforcer, enforcer.Close, nil
}

// Provider is the exported symbol that beckn-onix plugin manager looks up.
var Provider = provider{}
