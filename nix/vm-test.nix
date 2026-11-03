# Boots a NixOS VM with a virtual GPU, starts Hyprland as a normal user, loads lanesnap's Lua and
# runs tests/smoke.sh against it. This is the approach Hyprland's own CI uses (see
# hyprwm/Hyprland nix/tests/default.nix): Hyprland cannot run without a DRM device, so the VM
# provides one (virtio-gpu) and a login seat.
{ src }:
{ pkgs, ... }:
{
  name = "lanesnap-vm";

  nodes.machine = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [ jq foot ];
    fonts.packages = [ pkgs.dejavu_fonts ];

    environment.variables = {
      XDG_RUNTIME_DIR = "/tmp";
      XDG_CACHE_HOME = "/tmp";
    };

    programs.hyprland.enable = true;
    xdg.portal.enable = pkgs.lib.mkForce false;
    services.speechd.enable = false;
    services.getty.autologinUser = "alice";
    users.users.alice.isNormalUser = true;
    system.stateVersion = "24.11";

    # `o.bind` is Omarchy's helper; this stand-in lets hypr/lanesnap.lua load unmodified.
    environment.etc."lanesnap-test.lua".text = ''
      o = {
        bind = function(keys, description, dispatcher, options)
          local opts = options or {}
          if description then opts.description = description end
          if type(dispatcher) == "string" then dispatcher = hl.dsp.exec_cmd(dispatcher) end
          hl.bind(keys, dispatcher, opts)
        end,
      }
      dofile("/home/alice/lanesnap/hypr/lanesnap.lua")
    '';

    virtualisation = {
      cores = 4;
      memorySize = 4096;
      resolution = { x = 1920; y = 1080; };
      qemu.options = [ "-vga none -device virtio-gpu-pci" ];
    };
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.succeed("cp -r ${src} /home/alice/lanesnap && chown -R alice:users /home/alice/lanesnap && chmod -R u+w /home/alice/lanesnap")

    machine.execute("su - alice -c 'Hyprland -c /etc/lanesnap-test.lua > /tmp/hyprland.out 2>&1 &'")
    machine.wait_until_succeeds("ls /tmp/hypr/*/.socket.sock", timeout=120)

    # hyprctl needs the instance signature; take the newest instance directory.
    env = "export HYPRLAND_INSTANCE_SIGNATURE=$(basename $(ls -dt /tmp/hypr/*/ | head -1)); export PATH=/home/alice/lanesnap/bin:$PATH;"

    print(machine.succeed(f"su - alice -c '{env} hyprctl version | head -2; hyprctl monitors -j | jq -c \".[] | {{name, width, height}}\"; hyprctl configerrors'"))

    # The bindings from hypr/lanesnap.lua must have registered.
    for d in ["Snap zones overlay", "Snap window to zone 1", "Drag window to a snap zone", "Toggle split / stack in column"]:
        machine.succeed(f"su - alice -c '{env} hyprctl binds -j | jq -e \"any(.[]; .description == \\\"{d}\\\")\"'")

    status, out = machine.execute(f"su - alice -c '{env} cd /home/alice/lanesnap && LANESNAP_TEST_WS=9 tests/smoke.sh 2>&1'")
    print(out)
    machine.execute("cp $(find /tmp/hypr -name '*.log' | head -1) /tmp/hyprland-internal.log || true")
    print(machine.execute("tail -30 /tmp/hyprland-internal.log")[1])
    assert status == 0, "lanesnap smoke test failed"
  '';
}
