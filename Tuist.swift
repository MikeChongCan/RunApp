import ProjectDescription

/// Tuist generates RunApp.xcodeproj from Project.swift: Scripts/generate.
let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            includeGenerateScheme: false
        )
    )
)
