package com.bettercast.bettercast

import com.ryanheise.audioservice.AudioServiceActivity

// audio_service needs its activity so the media session survives the UI.
class MainActivity : AudioServiceActivity()
