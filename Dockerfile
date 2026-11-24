FROM swift:6.0

WORKDIR /workspace

COPY Package.swift ./
COPY Sources/PromptQuietCore ./Sources/PromptQuietCore
COPY Tests/PromptQuietCoreTests ./Tests/PromptQuietCoreTests

RUN swift build -c release

CMD ["swift", "test"]
