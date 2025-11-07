# Contributing to OpenTelemetry Bug Bash

## Bug Bash Guidelines

### Finding Bugs

When you find issues during the bug bash:

1. **Check for duplicates** - Search existing issues first
2. **Reproduce** - Verify the issue is reproducible
3. **Document** - Record detailed steps to reproduce
4. **Report** - File a clear, actionable bug report

### Bug Report Template

```markdown
## Description
Brief description of the issue

## Environment
- Service: [.NET/Java/Go]
- Deployment: [VM/AKS]
- Date/Time: [When did it occur?]

## Steps to Reproduce
1. Step one
2. Step two
3. Step three

## Expected Behavior
What should happen?

## Actual Behavior
What actually happened?

## Logs
```
Paste relevant logs here
```

## Trace Information
- Trace ID: [if applicable]
- Span ID: [if applicable]

## Screenshots
[If applicable]

## Additional Context
Any other relevant information
```

### Testing Scenarios

Focus on these areas:

1. **Trace Propagation**
   - Verify traces span all three services
   - Check parent-child relationships
   - Validate trace context propagation

2. **Auto-Instrumentation**
   - Confirm Java service traces without code changes
   - Verify automatic span creation
   - Check instrumentation quality

3. **Manual Instrumentation**
   - Test .NET and Go custom spans
   - Verify span attributes
   - Check event recording

4. **Error Handling**
   - Trigger errors in each service
   - Verify error propagation
   - Check error attributes in traces

5. **Performance**
   - Monitor overhead of instrumentation
   - Check trace sampling
   - Verify exporter performance under load

6. **Configuration**
   - Test different OTLP endpoints
   - Verify environment variable handling
   - Check configuration precedence

## Code Contributions

### Making Changes

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

### Coding Standards

- **.NET**: Follow Microsoft coding conventions
- **Java**: Follow Google Java Style Guide
- **Go**: Follow Effective Go guidelines

### Pull Request Process

1. Update documentation for any changes
2. Add tests if applicable
3. Ensure all tests pass
4. Update README.md with details of changes
5. Request review from maintainers

## Questions?

If you have questions during the bug bash, please reach out to the team lead or check the documentation.
