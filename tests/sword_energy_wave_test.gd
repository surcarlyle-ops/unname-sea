extends SceneTree
var failures: int = 0
var player: Node3D
var hands: Node3D
var waves: int = 0
class Target:
    extends Node3D
    var dead: bool = false
    var hits: int = 0
    var last_damage: int = 0
    func damage_point() -> Vector3:
        return global_position
    func apply_damage(amount: int, _push: Vector3) -> void:
        hits += 1
        last_damage = amount
func _initialize() -> void:
    run.call_deferred()
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error(message)
func pose() -> void:
    var p: float = player._wave_elapsed / player._wave_duration() if player._wave_elapsed >= 0 else -1.0
    hands.update_pose(1.0/60,0,false,-1,0,true,2,{"wave_progress":p})
func run() -> void:
    var arena = load("res://scenes/combat_mvp.tscn").instantiate()
    root.add_child(arena)
    current_scene = arena
    await process_frame
    player = arena.player
    player.set_controls_active(true)
    player.set_physics_process(false)
    player.grapple.set_physics_process(false)
    arena.guardian.set_physics_process(false)
    arena.guardian.dead = true
    arena.hud.visible = false
    player.position = Vector3(0,0.08,12)
    player.selected_slot = 0
    player._refresh_weapon()
    hands = player.hands
    hands._cancel_spawn_animation()
    for i: int in range(40):
        pose()
        await process_frame
    hands.set_energy_glow(1.0)
    await capture("charged")
    check(not hands._tide_glow.mesh is BoxMesh,"Blade charge uses actual mesh, no box")
    check(hands._tide_glow_material is ShaderMaterial,"Blade charge uses flowing surface shader")
    player.energy = 3
    player.wave_released.connect(count_wave)
    check(player.release_wave(),"Full energy starts horizontal cast")
    check(player.energy == 0 and waves == 0,"Energy consumed; no projectile before slash")
    check(not player.request_attack() and not player.release_wave(),"Cast blocks overlapping attacks")
    player._update_wave(0.14)
    pose()
    await capture("windup")
    check(waves == 0,"Windup does not fire early")
    player._update_wave(0.07)
    pose()
    check(waves == 1,"One projectile launches on outward cut")
    var wave: Node3D = arena.get_child(arena.get_child_count()-1)
    wave.set_physics_process(false)
    wave._physics_process(0.08)
    hands.set_energy_glow(0.0)
    await capture("release")
    check(wave.get_child_count() == 3,"Crescent plus two wake layers")
    for child: Node in wave.get_children():
        check(child is MeshInstance3D and not child.mesh is BoxMesh,"Wave is curved mesh, not a box")
    var target: Target = Target.new()
    arena.add_child(target)
    target.add_to_group("mvp_enemies")
    target.global_position = wave.global_position
    wave._check_targets()
    wave._check_targets()
    check(target.hits == 1 and target.last_damage == 18,"Wave retains damage and single hit per target")
    player._update_wave(0.12)
    pose()
    wave.position += Vector3(0,0,-0.6)
    await capture("followthrough")
    player._update_wave(0.50)
    pose()
    check(player._wave_elapsed < 0 and waves == 1,"Recovery ends; no duplicate projectile")
    player.energy = 3
    check(player.release_wave(),"Can cast again after recovery")
    player.selected_slot = 3
    player._refresh_weapon()
    player._update_wave(1.0)
    check(player._wave_elapsed < 0 and waves == 1,"Weapon switch cancels pending wave")
    print("SWORD_ENERGY_RESULT failures=", failures)
    quit(0 if failures == 0 else 1)
func count_wave() -> void:
    waves += 1
func capture(label: String) -> void:
    await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://.mvp_qa/sword_energy/"+label+".png")
