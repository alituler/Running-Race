#include <vector>
#include <cstdlib>
#include <assert.h>
#include <stdlib.h>
#include <stddef.h>
#include <time.h>
#include <stdio.h>
#include <curand.h>
#include <iostream>
#include <random>
#include <thread>
#include <chrono>
#include <algorithm>

#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include <cuda_runtime.h>
#include <cuda.h>



// Constants
const int NUM_RUNNERS = 100;
const int RUNWAY_LENGTH = 100;
__device__ int order = 0;
__device__ int oneRunnerHasReached = 0;

// Runner class
class Runner {
public:
    // Constructor
    Runner() : code_(0), position_(0.0f), speed_(0.0f), final_order_(order) { }

    int getCode() const { return code_; }
    void setCode(int code) { code_ = code; }

    // Getter and setter for position
    float getPosition() const { return position_; }
    void setPosition(float position) { position_ = position; }

    // Getter and setter for speed
    float getSpeed() const { return speed_; }
    void setSpeed(float speed) { speed_ = speed; }

    int getFinalOrder() const { return final_order_; }
    void setFinalOrder(int final_order) { final_order_ = final_order; }
    // Update the runner's position based on their speed
    __host__ __device__ void updatePosition() {
        // Calculate the new position
        float newPosition = position_ + speed_;
        // Check if the runner has reached the end of the runway
        if (position_ >= 100) {
            position_ = 100;
        }
        else {
            if (newPosition >= RUNWAY_LENGTH) {
                order++;
                // Set the position to the end of the runway
                position_ = RUNWAY_LENGTH;
                final_order_ = order;

                //std::cout << "Runner " << final_order_ << " has finished the race at position " << position_ << "m" << std::endl;
            }
            else {
                // Update the position
                position_ = newPosition;
            }
        }



    }

private:
    int code_;       // The code of the runner
    float position_;  // The current position of the runner
    float speed_;     // The current speed of the runner
    int final_order_; //// The final position of the runner
};

// Random number generator
std::mt19937 rng;

// Function to generate a random speed for a runner
float generateRandomSpeed() {
    // Create a uniform distribution in the range [1, 5]
    std::uniform_real_distribution<float> dist(1.0f, 5.0f);

    // Generate and return a random number
    return dist(rng);
}
//Function to sort runners by current positions
bool compareRunnersByCurrentPositions(const Runner& a, const Runner& b) {
    return a.getPosition() > b.getPosition();
}
//Function to sort runners by final positions
bool compareRunnersByFinalOrder(const Runner& a, const Runner& b) {
    return a.getFinalOrder() < b.getFinalOrder();
}

// Function to print the positions of all runners
void printRunnerPositions(const Runner* runners) {
    // Print the position of each runner
    int finishedRunner = 0;
    for (int i = 0; i < NUM_RUNNERS; i++) {
        // Check if the current runner has reached the end of the runway
        if (runners[i].getPosition() >= RUNWAY_LENGTH && runners[i].getFinalOrder() == 1 && oneRunnerHasReached == 0) {
            finishedRunner = 1;

            std::cout << "\nRunner " << runners[i].getCode() << " has reached the end of the runway for the first time!" << std::endl;

        }
    }
    if (finishedRunner == 1) {
        std::cout << std::endl;

        std::cout << "Runner Code: \t Runner Location:" << std::endl;

        for (int i = 0; i < NUM_RUNNERS; i++) {
            oneRunnerHasReached++;
            std::cout << "Runner " << runners[i].getCode() << ":\t " << runners[i].getPosition() << "m" << std::endl;

        }
        std::cout << std::endl;
    }



    std::cout << "The race is in progress! " << std::endl;


}


// Function to print the positions of all runners
void printRunnerPositionsAfterAllFinishedTheRace(const Runner* runners) {
    std::cout << "\nThe race is over.\nHere are the results:\n" << std::endl;
    std::cout << "Runner Code: \t Runner Position:\n" << std::endl;

    for (int i = 0; i < NUM_RUNNERS; i++) {
        std::cout << "Runner " << runners[i].getCode() << ": " << runners[i].getPosition() << "m\t\t" << runners[i].getFinalOrder() << std::endl;
    }

    std::cout << std::endl;
}

// CUDA kernel to update the positions of all runners
__global__ void updateRunnerPositions(Runner* runners) {
    // Get the index of the current thread
    int threadIndex = blockDim.x * blockIdx.x + threadIdx.x;

    // Check if the current thread is within the range of runners
    if (threadIndex < NUM_RUNNERS) {
        // Update the position of the current runner
        runners[threadIndex].updatePosition();
    }
}

int main() {
    std::cout << "A 100m running race is held in which 100 runners participate.\nRunners have instant position and instant speed.\nThis speed changes randomly between a minimum of 1 meter/second and a maximum of 5 meters/second.\nEach runner is calculated in parallel by different Threads on the graphics card.\nThe graphics card runs once per second, and the new instantaneous position of all runners is calculated at each run.\nWhen the first runner reaches the finish line, the current position of all runners is printed sequentially.\nWhen all runners finish the race, the ranking of the race is printed on the screen.\n" << std::endl;

    // Seed the random number generator
    rng.seed(std::random_device()());

    // Allocate memory for the runners on the device
    Runner* deviceRunners;
    cudaMalloc(&deviceRunners, sizeof(Runner) * NUM_RUNNERS);

    // Allocate memory for the runners on the host
    Runner* hostRunners = new Runner[NUM_RUNNERS];

    for (int i = 0; i < NUM_RUNNERS; i++) {
        hostRunners[i].setCode(i + 1);
        hostRunners[i].setPosition(0.0f);
        hostRunners[i].setSpeed(0.0f);
        hostRunners[i].setFinalOrder(0);
        //hostRunners[i].setSpeed(generateRandomSpeed());

    }

    // Loop until all runners have reached the end of the runway
    bool allRunnersFinished = false;
    while (!allRunnersFinished) {
        //For everytime generated random speed for all runners 
        // Initialize the runners
        for (int i = 0; i < NUM_RUNNERS; i++) {
            hostRunners[i].setSpeed(generateRandomSpeed());
        }

        // Copy the host runners to the device
        cudaMemcpy(deviceRunners, hostRunners, sizeof(Runner) * NUM_RUNNERS, cudaMemcpyHostToDevice);

        // Launch the CUDA kernel to update the positions of the runners
        updateRunnerPositions << <1, NUM_RUNNERS >> > (deviceRunners);

        // Copy the updated runners back to the host
        cudaMemcpy(hostRunners, deviceRunners, sizeof(Runner) * NUM_RUNNERS, cudaMemcpyDeviceToHost);

        // Check if all of the runners have finished the race
        allRunnersFinished = true;
        for (int i = 0; i < NUM_RUNNERS; i++) {
            if (hostRunners[i].getPosition() < RUNWAY_LENGTH) {
                allRunnersFinished = false;
                break;
            }
        }
        std::this_thread::sleep_for(std::chrono::seconds(1));

        //Sort all runners by current positions.
        std::sort(hostRunners, hostRunners + NUM_RUNNERS, compareRunnersByCurrentPositions);

        // Print the positions of the runners
        printRunnerPositions(hostRunners);
    }

    //Sort all runners by final positions.
    std::sort(hostRunners, hostRunners + NUM_RUNNERS, compareRunnersByFinalOrder);
    //Print all runners positions after the race.
    printRunnerPositionsAfterAllFinishedTheRace(hostRunners);

    // Free the memory allocated for the runners on the device and host
    cudaFree(deviceRunners);
    delete[] hostRunners;

    return 0;
}
