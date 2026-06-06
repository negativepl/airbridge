package com.airbridge.mirror

/** Czy `component` (pakiet/usługa) jest na liście włączonych usług dostępności
 *  (Settings.Secure "enabled_accessibility_services", rozdzielona ":"). */
fun accessibilityServiceEnabled(enabledServices: String?, component: String): Boolean {
    if (enabledServices.isNullOrEmpty()) return false
    return enabledServices.split(":").any { it.equals(component, ignoreCase = true) }
}
