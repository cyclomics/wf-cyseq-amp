The system design is divided into several viewpoints. Each viewpoint, describes one aspect of the workflow, and what practices and philosphies should be followed. Here we propose a series of questions that should be answered per viewpoint. Keep in mind that depending on the workflow, not all questions might be relevant and can be skipped. Of course, additional information can be written into the adequate viewpoint even if it is not an answer to one of these questions. **It is as important to write the design as to explain the reason behind each decision**, in this manner it is easier for multiple people to follow the same principles.

### 1. Context Viewpoint

*Describe the system’s environment and boundaries*

- What is the main purpose of the workflow? 
  - Try to be as concrete as possible, this is very important as it defines what the tool should do, and what it should not.
  - Think whether it has a single purpose or multiple; if it has multiple purposes, should it be split into different tools? Argue why it should be a single tool.
  - Explain the biological application for which the tool is developed. If possible, mention a biological application for which a user might expect the tool to be applicable, but for which it is either not applicable.
  - Example:
    - *This workflow takes as input a series of FASTQ files, aligns them, and creates a series of report files on certain statistics.*
    - *The tool is developed for CyclomicsSeq sequencing amplicons, with insert sizes ranging from 100-500 bp.*
    - *This tool is not applicable for other sequencing technologies.*

- Who is the intended user of the tool?
  - Probably, most Cyclomics tools will be used by experienced bioinformaticians that are comfortable with the CLI, but consider this also for notebook repositories.
  - Examples: Bioinformatician, wetlab person, technician, researcher.

- What does the tool NOT do and why? For example, data will not be aligned, it is expected to be aligned. It will not do variant calling, we reserve this to external tools. It will report metrics, but not make plots.

### 2. Composition and Structure Viewpoint

*Describe how the system is decomposed into parts*

- What are the main components/modules of the workflow? 
  - How are the different modules organized? 
  - What are the responsibilities of each module?
    - What does a module do, and what does it not do
    - Where does the responsibility of a module start and end?
  - Should modules be organized by steps in a processing pipeline?
  - Should modules be different alternatives of the same step in a processing pipeline?
  - Should modules be organized by different input file types?
  
### 3. Logical Viewpoint

*Describe the system’s functional behavior and domain abstractions*

- What are the entry points of data?
  - Is this a real-time workflow? Does it handle a stream of data over time? When conditions close the stream of input data?
- What are the output points of data?
- Are results deterministic? Is there a seed setting?
- How are we organizing the processes for easy testing?

### 4. Dependency Viewpoint

*Show what the system depends on what, and why.*

- What is the philosophy behind environment/containers?
  - Single container for the whole workflow?
  - Container per process?
  - Versioning of containers and the tools inside
  - Are containers shared between processes?

- Do we allow plugins in the workflow?

- How do we handle updates to tools?

- How much do we shape the workflow relative to the tools? For example, given two tools that do the same job which one should be chosen:
  - one processes a single file in a single core into a single output file
  - one processes a set of files in a single core into a dir with multiple files
  - one processes a single file with multiple cores into a single output file
  - one processes a set of files with multiple cores into a dir with multiple files

- If two tools that do the same job are implemented (e.g. in different modules following a strategy pattern), what are the dependency implications? How should they be handled (e.g. separate containers)

- Environment assumptions (OS, environment paths, installed tools, filesystem permissions)

### 5. Information Viewpoint

*Describe the structure and lifecycle of data.*

- What kind of inputs are expected?
  - File formats. What type of file formats do we expect? How will we handle these file formats, do we need external libraries or will we write our own parsers?
  - How much validation will be done on the input data?
  - Amount of data. How much data will we processing? Are there lots of large files, small files, or a single large or small file?
  
- What kind of outputs are expected?
  - Should we have multiple files as outputs?
  - Should we have a single file as output?

- Do we keep intermediate files?
- How explicit are we with input files? 
  - Do we try to find a file if not given?
  - Do we have defaults?
  - When do we use defaults?

- How much parallelization is done in the workflow vs within the tool? How should we configure the tools in that regard? How should we choose the tools in that regard?
  - one processes a single file in a single core into a single output file
  - one processes a set of files in a single core into a dir with multiple files
  - one processes a single file with multiple cores into a single output file
  - one processes a set of files with multiple cores into a dir with multiple files

### 6. Patterns Use Viewpoint

*Explain the design patterns used and their rationale.*

- Do you use a pipeline pattern where the output from one step is the input for the next?
- Is there a standard skip pattern? (e.g input -> A into output C with optional step B in between)
- Is there a standard aggregate pattern?  (e.g input -> A1, A2, A3 into output -> B)
- Is there a standard split pattern? (e.g input -> A into output -> B1, B2, B3)
- Is there a standard strategy pattern (e.g. input -> A1 OR A2 into output -> B)

### 7. Interface and Interaction Viewpoint

*Define all exposed interfaces.*

- Is there a CLI interface?
- Is there a GUI interface? Is it integrated into a GUI platform (e.g. EPI2ME)?
- How are Error and exit code semantics organized?
- Are there any file naming conventions?
- What is printed to stdout?
- How is logging performed? What are the different levels of logging? What should go into info, warning, debug?
- What type of configuration parameters do we expect? 
  - General configuration parameters (settings that are only set once).
  - Per call configuration parameters (settings that might change everytime the tool is used).
  - What is the expected experience of the user in choosing the right settings?
  - How will user settings be differentiated from developer settings? For example, --input-path is a user setting, while --max-window-size is probably something more internal. 

### 8. State Dynamics Viewpoint

*Describe how the system’s state changes over time.*

- Is input data validated at the start of the process or the entire (sub)workflow?
- If there is an error, do we stop completely, or do we try to keep running as many other processes as possible?
- How can you know that an output file is complete?

### 9. Algorithm Viewpoint

*Describe core algorithms and their properties.*

- If your code includes scripts, explain any relevant algorithms. For example, is an in-house script used for variant calling? How does it work?

### 10. Resource Viewpoint

*Describe resource usage and constraints.*

- What is the expected max memory usage?
- How does memory scale with additional cores?
- How does runtime scale with additional cores?
- Are there steps where there are memory peaks?
- What is the expected run time given a certain amount of input?
- What is the output file size expected given a certain amount of input?