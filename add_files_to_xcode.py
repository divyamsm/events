#!/usr/bin/env python3
import uuid
import re

# Read the project file
with open('StepOut/StepOut.xcodeproj/project.pbxproj', 'r') as f:
    content = f.read()

# Generate unique IDs for the new files
files_to_add = [
    ('BlockedUsersManager.swift', str(uuid.uuid4()).replace('-', '').upper()[:24]),
    ('BlockedUsersView.swift', str(uuid.uuid4()).replace('-', '').upper()[:24]),
    ('TermsOfService.swift', str(uuid.uuid4()).replace('-', '').upper()[:24])
]

# Find the PBXFileReference section
file_ref_pattern = r'(FF1A4CE429A1A2D000000123 /\* ProfileView\.swift \*/.*?sourceTree = "<group>";)'
file_ref_match = re.search(file_ref_pattern, content, re.DOTALL)

if file_ref_match:
    # Add PBXFileReference entries
    new_file_refs = []
    for filename, file_id in files_to_add:
        new_file_refs.append(f'\t\t{file_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};')

    # Insert after ProfileView.swift
    insert_pos = file_ref_match.end()
    content = content[:insert_pos] + '\n' + '\n'.join(new_file_refs) + content[insert_pos:]

# Find the PBXGroup section (children list for StepOut group)
group_pattern = r'(B6A2F53817229565D50548F7 /\* EventPhotosViewModel\.swift \*/,)'
group_match = re.search(group_pattern, content)

if group_match:
    # Add file references to the group
    new_group_refs = []
    for filename, file_id in files_to_add:
        new_group_refs.append(f'\t\t\t\t{file_id} /* {filename} */,')

    insert_pos = group_match.end()
    content = content[:insert_pos] + '\n' + '\n'.join(new_group_refs) + content[insert_pos:]

# Find the PBXSourcesBuildPhase section
sources_pattern = r'(FF1A4CE429A1A2D000000224 /\* ProfileView\.swift in Sources \*/,)'
sources_match = re.search(sources_pattern, content)

if sources_match:
    # Add PBXBuildFile entries
    new_build_refs = []
    for filename, file_id in files_to_add:
        build_id = str(uuid.uuid4()).replace('-', '').upper()[:24]
        # Add to build file section at the top
        build_file_entry = f'\t\t{build_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {filename} */; }};'

        # Find the PBXBuildFile section and add there
        build_file_pattern = r'(/\* Begin PBXBuildFile section \*/)'
        build_file_match = re.search(build_file_pattern, content)
        if build_file_match:
            insert_pos = build_file_match.end()
            content = content[:insert_pos] + '\n' + build_file_entry + content[insert_pos:]

        # Add to sources phase
        new_build_refs.append(f'\t\t\t\t{build_id} /* {filename} in Sources */,')

    insert_pos = sources_match.end()
    content = content[:insert_pos] + '\n' + '\n'.join(new_build_refs) + content[insert_pos:]

# Write the modified content back
with open('StepOut/StepOut.xcodeproj/project.pbxproj', 'w') as f:
    f.write(content)

print("Successfully added files to Xcode project:")
for filename, file_id in files_to_add:
    print(f"  - {filename} ({file_id})")
