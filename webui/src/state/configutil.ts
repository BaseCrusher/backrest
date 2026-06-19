import { Auth, Config } from "../../gen/ts/v1/config_pb";

export const AUTH_DRIVER_DISABLED = "disabled";
export const AUTH_DRIVER_LOCAL = "local";
export const AUTH_DRIVER_OIDC = "oidc";

// effectiveAuthDriver mirrors config.AuthDriverOf in the Go backend.
// Precedence: deprecated `disabled` flag wins, then auth_driver, empty -> local.
export const effectiveAuthDriver = (auth?: Auth): string => {
  if (!auth) return AUTH_DRIVER_DISABLED;
  if (auth.disabled) return AUTH_DRIVER_DISABLED;
  if (!auth.authDriver) return AUTH_DRIVER_LOCAL;
  return auth.authDriver;
};

export const isAuthDisabled = (auth?: Auth): boolean =>
  effectiveAuthDriver(auth) === AUTH_DRIVER_DISABLED;

export const shouldShowSettings = (config: Config) => {
  return (
    !config.instance ||
    !config.auth ||
    (effectiveAuthDriver(config.auth) === AUTH_DRIVER_LOCAL &&
      config.auth.users.length === 0)
  );
};
