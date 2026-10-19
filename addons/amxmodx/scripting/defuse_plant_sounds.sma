#include <amxmodx>
#include <csx>
#include <engine>

#define PLUGIN "Plant/Defuse Sounds"
#define VERSION "0.1"
#define AUTHOR " "

// Caminho dos sons originais do CS 1.6
new const SOUND_PLANT[] = "weapons/c4_plant.wav";
new const SOUND_DEFUSE[] = "weapons/c4_disarm.wav";

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);
}

public plugin_precache() {
    // Pré-carrega os sons para evitar travamentos
    precache_sound(SOUND_PLANT);
    precache_sound(SOUND_DEFUSE);
}

// Evento chamado no momento em que o TR começa a plantar a bomba
public bomb_planting(id) {
    // Emite o som do plant no canal da arma, volume normal e distância padrão (audível para quem estiver perto)
    emit_sound(id, CHAN_WEAPON, SOUND_PLANT, VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
}

// Evento chamado no momento em que o CT começa a defusar a bomba
public bomb_defusing(id) {
    // Emite o som do defuse no canal da arma
    emit_sound(id, CHAN_WEAPON, SOUND_DEFUSE, VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
}