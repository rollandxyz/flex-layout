#!/bin/bash

# Script to publish the build artifacts to a GitHub repository.
# Builds will be automatically published once new changes are made to the repository.

# The script should immediately exit if any command in the script fails.
set -e

# Go to the project root directory
cd $(dirname ${0})/../..

if [ -z ${FLEX_LAYOUT_BUILDS_TOKEN} ]; then
  echo "Error: No access token for GitHub could be found." \
       "Please set the environment variable 'FLEX_LAYOUT_BUILDS_TOKEN'."
  exit 1
fi

# Flex-Layout packages that need to published.
PACKAGES=(flex-layout)
REPOSITORIES=(flex-layout-builds)

# Command line arguments.
COMMAND_ARGS=${*}

# Function to publish artifacts of a package to Github.
#   @param ${1} Name of the package
#   @param ${2} Repository name of the package.
publishPackage() {
  packageName=${1}
  packageRepo=${2}

  srcDir=$(pwd)
  buildDir="dist/releases/${packageName}"
  buildVersion=$(node -pe "require('./package.json').version")

  commitSha=$(git rev-parse --short HEAD)
  commitAuthorName=$(git --no-pager show -s --format='%an' HEAD)
  commitAuthorEmail=$(git --no-pager show -s --format='%ae' HEAD)
  commitMessage=$(git log --oneline -n 1)

  repoUrl="https://github.com/angular/${packageRepo}.git"
  repoDir="tmp/${packageRepo}"

  if [[ ! ${COMMAND_ARGS} == *--no-build* ]]; then
    # Create a release of the current repository.
    $(npm bin)/gulp ${packageName}:build-release:clean
  fi

  # Prepare cloning the builds repository
  rm -rf ${repoDir}
  mkdir -p ${repoDir}

  # Clone the repository and only fetch the last commit to download less unused data.
  git clone ${repoUrl} ${repoDir} --depth 1

  # Copy the build files to the repository
  rm -rf ${repoDir}/*
  cp -r ${buildDir}/* ${repoDir}

  # Copy the npm README.md to the flex-layout-builds dir...
  cp -f "scripts/release/README.md" ${repoDir}

  # Create the build commit and push the changes to the repository.
  cd ${repoDir}

 # Replace the version in every file recursively with a more specific version that also includes
  # the SHA of the current build job. Normally this "sed" call would just replace the version
  # placeholder, but the version placeholders have been replaced by the release task already.
  sed -i "s/${buildVersion}/${buildVersion}-${commitSha}/g" $(find . -type f)

  cp -f "${srcDir}/CHANGELOG.md" ./

  # Prepare Git for pushing the artifacts to the repository.
  git config user.name "${commitAuthorName}"
  git config user.email "${commitAuthorEmail}"
  git config credential.helper "store --file=.git/credentials"

  echo "https://${FLEX_LAYOUT_BUILDS_TOKEN}:@github.com" > .git/credentials

  git add -A
  git commit --allow-empty -m "${commitMessage}"
  git tag "${buildVersion}-${commitSha}"
  git push origin master --tags

  echo "Published package artifacts for ${packageName}#${commitSha}."
}

for ((i = 0; i < ${#PACKAGES[@]}; i++)); do
  packageName=${PACKAGES[${i}]}
  packageRepo=${REPOSITORIES[${i}]}

  # Publish artifacts of the current package. Run publishing in a sub-shell to avoid working
  # directory changes.
  (publishPackage ${packageName} ${packageRepo})
done
